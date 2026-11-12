# frozen_string_literal: true

# Downloads a GitHub release asset onto an EC2 instance and extracts it
# into /home/bz-app/<service_name>, replacing a git clone + install.
module GithubReleaseInstaller
  TAG_PATTERN = /\A[A-Za-z0-9._-]{1,128}\z/.freeze
  OWNER_REPO_PATTERN = /\A[A-Za-z0-9._-]+\z/.freeze
  SSH_REPO_PATTERN = /\Agit@github\.com:([^\/]+)\/([^\/]+?)(?:\.git)?\z/.freeze
  TOKEN_REMOTE_PATH = '/tmp/btrz-gh-token'
  CURL_CONFIG_REMOTE_PATH = '/tmp/btrz-gh-curl.conf'
  SCRIPT_REMOTE_PATH = '/tmp/btrz-gh-install.sh'

  module_function

  def token_from_env!
    token = ENV['GH_TOKEN'].to_s.strip
    token = ENV['GITHUB_TOKEN'].to_s.strip if token.empty?
    raise ArgumentError, 'GH_TOKEN or GITHUB_TOKEN is required for --github_release' if token.empty?

    token
  end

  def validate_tag!(tag)
    value = tag.to_s
    raise ArgumentError, 'github_release tag is required' if value.empty?
    raise ArgumentError, "unsafe github_release tag: #{value.inspect}" unless value.match?(TAG_PATTERN)

    value
  end

  def parse_github_repo(git_url)
    match = git_url.to_s.match(SSH_REPO_PATTERN)
    raise ArgumentError, "github_release requires a git@github.com SSH repo, got: #{git_url.inspect}" if match.nil?

    owner = match[1]
    repo = match[2]
    unless owner.match?(OWNER_REPO_PATTERN) && repo.match?(OWNER_REPO_PATTERN)
      raise ArgumentError, "unsafe github owner/repo in #{git_url.inspect}"
    end

    { owner: owner, repo: repo }
  end

  def extract_command_for(asset_name, dest_dir)
    name = asset_name.to_s
    if name.end_with?('.tar.gz')
      "tar -xzf \"#{name}\" -C \"#{dest_dir}\""
    elsif name.end_with?('.zip')
      "(command -v unzip >/dev/null && unzip -q \"#{name}\" -d \"#{dest_dir}\") || python3 -m zipfile -e \"#{name}\" \"#{dest_dir}\""
    else
      raise ArgumentError, "unsupported release asset extension: #{name.inspect}"
    end
  end

  # Installs the single uploaded asset for tag into /home/bz-app/<service_name>.
  # +instance+ must respond to upload_data_to_file, run_ssh_command!, and notify.
  def install_on_instance(instance, service_name:, git_repo:, tag:, build_number:)
    safe_tag = validate_tag!(tag)
    parsed = parse_github_repo(git_repo)
    token = token_from_env!
    owner = parsed[:owner]
    repo = parsed[:repo]
    app_dir = "/home/bz-app/#{service_name}"
    work_dir = "/tmp/btrz-gh-release-#{service_name}"

    instance.notify("github release (#{service_name}): loading #{owner}/#{repo}@#{safe_tag}")
    instance.upload_data_to_file(token, TOKEN_REMOTE_PATH)
    instance.run_ssh_command!("chmod 600 #{TOKEN_REMOTE_PATH}")

    script = remote_install_script(
      owner: owner,
      repo: repo,
      tag: safe_tag,
      app_dir: app_dir,
      work_dir: work_dir
    )
    # Token and script are separate files; keep the token out of notify and SSH argv.
    instance.upload_data_to_file(script, SCRIPT_REMOTE_PATH)
    instance.run_ssh_command!("bash #{SCRIPT_REMOTE_PATH}")
    instance.write_build_number_file(build_number)
    instance.notify("github release (#{service_name}): ready at #{app_dir}")
  end

  def remote_install_script(owner:, repo:, tag:, app_dir:, work_dir:)
    api_url = "https://api.github.com/repos/#{owner}/#{repo}/releases/tags/#{tag}"
    <<~SCRIPT
      #!/usr/bin/env bash
      set -euo pipefail
      cleanup() {
        rm -f #{TOKEN_REMOTE_PATH} #{CURL_CONFIG_REMOTE_PATH} #{SCRIPT_REMOTE_PATH}
        rm -rf #{work_dir}
      }
      trap cleanup EXIT

      TOKEN=$(cat #{TOKEN_REMOTE_PATH})
      {
        echo "header = \\"Authorization: Bearer ${TOKEN}\\""
        echo 'header = "Accept: application/vnd.github+json"'
        echo 'header = "X-GitHub-Api-Version: 2022-11-28"'
      } > #{CURL_CONFIG_REMOTE_PATH}
      chmod 600 #{CURL_CONFIG_REMOTE_PATH}
      rm -f #{TOKEN_REMOTE_PATH}

      RELEASE_JSON=$(curl -fsSL --config #{CURL_CONFIG_REMOTE_PATH} "#{api_url}")
      ASSET_COUNT=$(printf '%s' "$RELEASE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('assets') or []))")
      if [ "$ASSET_COUNT" != "1" ]; then
        echo "expected exactly one release asset, got $ASSET_COUNT" >&2
        exit 1
      fi
      ASSET_NAME=$(printf '%s' "$RELEASE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['assets'][0]['name'])")
      ASSET_URL=$(printf '%s' "$RELEASE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['assets'][0]['url'])")
      case "$ASSET_NAME" in
        *.tar.gz|*.zip) ;;
        *)
          echo "unsupported release asset extension: $ASSET_NAME" >&2
          exit 1
          ;;
      esac

      rm -rf #{work_dir}
      mkdir -p #{work_dir}
      cd #{work_dir}
      {
        echo "header = \\"Authorization: Bearer ${TOKEN}\\""
        echo 'header = "Accept: application/octet-stream"'
        echo 'header = "X-GitHub-Api-Version: 2022-11-28"'
      } > #{CURL_CONFIG_REMOTE_PATH}
      curl -fsSL --config #{CURL_CONFIG_REMOTE_PATH} -o "$ASSET_NAME" "$ASSET_URL"
      unset TOKEN

      sudo rm -rf #{app_dir}
      sudo mkdir -p #{app_dir}
      if [[ "$ASSET_NAME" == *.tar.gz ]]; then
        sudo tar -xzf "$ASSET_NAME" -C #{app_dir}
      else
        if command -v unzip >/dev/null; then
          sudo unzip -q "$ASSET_NAME" -d #{app_dir}
        else
          sudo python3 -m zipfile -e "$ASSET_NAME" #{app_dir}
        fi
      fi
      ENTRIES=$(sudo find #{app_dir} -mindepth 1 -maxdepth 1 | wc -l)
      if [ "$ENTRIES" = "1" ]; then
        ONLY=$(sudo find #{app_dir} -mindepth 1 -maxdepth 1)
        if sudo test -d "$ONLY"; then
          sudo find "$ONLY" -mindepth 1 -maxdepth 1 -exec mv {} #{app_dir}/ \\;
          sudo rmdir "$ONLY"
        fi
      fi
      sudo chown -R bz-app:bz-app #{app_dir}
    SCRIPT
  end
end

create_server.rb
==================
Create a server.

Options:
-------------
* `--env` - the environment (staging,production and so on) **required**.
* `--build_number` - server build number. **required**.
* `--service_file` - the yml file location (full path). **required**.
* `--dont_push` - Mostly for testing purposes, will not push this instance to a load balancer if it is a load balancer instance.
      instances who are not load balancing instances will not be push regardless. default to `false`.
* `--force_create` - create a server even if one exists. defaults to `false`
* `--servers_count` - how many server to create, default to `1`.
* `--branch` - git branch to deploy. When non-empty, replaces `deployment.source.branch_name` (including the value selected by the environment `override` section) on every git source. When omitted or blank, the branch from `service.yml` is used.
* `--github_release TAG` - for every `deployment.source.type: git` app, download that GitHub release's single uploaded asset onto the instance and extract it into `/home/bz-app/<service_name>` instead of cloning. Skips `machine.install` and `machine.fast_install` (the asset is the finished tree). The repo still comes from `service.yml` (`git@github.com:...`). The release must have exactly one uploaded asset whose name ends in `.zip` or `.tar.gz`. Requires `GH_TOKEN` or `GITHUB_TOKEN` in the environment of the process that runs `create_server.rb` (the token is uploaded to a temporary file on the instance for `curl`, then deleted). Other source types (`s3`, `gcs_docker`, `nop`) are unchanged.

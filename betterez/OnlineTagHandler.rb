# frozen_string_literal: true

# Sets the EC2 Online tag and starts Grafana Alloy only after the instance is serving.
module OnlineTagHandler
  def apply_online_tag(online)
    update_tag_value('Online', online ? 'yes' : 'no')
    restart_startup_download_for_alloy if online
  end

  def restart_startup_download_for_alloy
    notify 'restarting startup-download so Grafana Alloy can start after Online=yes'
    run_ssh_command('sudo systemctl restart startup-download.service')
  rescue StandardError => error
    notify "failed to restart startup-download: #{error}"
  end
end

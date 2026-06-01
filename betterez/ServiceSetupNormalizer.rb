# frozen_string_literal: true

# Normalizes service YAML that may define multiple co-hosted applications
# under `applications`, while preserving backward compatibility with a single
# root-level `deployment` + `machine`.
module ServiceSetupNormalizer
  module_function

  def multi_app?(service_setup)
    apps = service_setup['applications']
    apps.is_a?(Array) && !apps.empty?
  end

  # Ordered list of { 'deployment' => ..., 'machine' => ... }.
  def applications_list(service_setup)
    apps = service_setup['applications']
    if apps.nil? || !apps.is_a?(Array) || apps.empty?
      return [{
        'deployment' => service_setup['deployment'],
        'machine' => service_setup['machine']
      }]
    end
    apps
  end

  # Index of the infrastructure-primary app: last entry with healthcheck.perform == true,
  # else last index in the list.
  def infrastructure_primary_index(service_setup)
    list = applications_list(service_setup)
    last_with_hc = nil
    list.each_with_index do |app, idx|
      dep = app['deployment']
      next unless dep.is_a?(Hash)

      hc = dep['healthcheck']
      last_with_hc = idx if hc.is_a?(Hash) && hc['perform'] == true
    end
    return last_with_hc unless last_with_hc.nil?

    list.length - 1
  end

  def infrastructure_primary_app(service_setup)
    applications_list(service_setup)[infrastructure_primary_index(service_setup)]
  end

  def infrastructure_primary_deployment(service_setup)
    infrastructure_primary_app(service_setup)['deployment']
  end

  def infrastructure_primary_service_name(service_setup)
    infrastructure_primary_deployment(service_setup)['service_name']
  end

  # AMI / packer image: root machine.image, else first non-empty among applications (in order).
  def machine_image_for_ami(service_setup)
    img = service_setup.dig('machine', 'image')
    return img if img && img.to_s != ''

    applications_list(service_setup).each do |app|
      mimg = app.dig('machine', 'image')
      return mimg if mimg && mimg.to_s != ''
    end
    nil
  end

  # Build a service_setup-shaped hash for one app (ServiceInstaller / load code).
  def merged_app_service_setup(root, app_entry)
    out = {}
    root.each do |k, _v|
      sk = k.to_s
      next if %w[deployment machine applications].include?(sk)

      out[k] = root[k]
    end
    out['deployment'] = app_entry['deployment'] || {}
    out['machine'] = app_entry['machine'] || {}
    out
  end

  # Sync root deployment + machine from primary so ELBClient and legacy code
  # that read service_setup['deployment'] see the load-balanced app.
  def sync_root_deployment_and_machine!(service_setup)
    return unless multi_app?(service_setup)

    primary = infrastructure_primary_app(service_setup)
    service_setup['deployment'] = Marshal.load(Marshal.dump(primary['deployment']))
    rm = service_setup['machine'].is_a?(Hash) ? service_setup['machine'] : {}
    pm = primary['machine'].is_a?(Hash) ? primary['machine'] : {}
    service_setup['machine'] = rm.merge(pm)
  end
end

About service files
=============
Every machine project(a project that requires a machine to run on, unlike mobile or automation) will typically includes a service file, describing:
* The type of machine required - this will be the packer image for the server creator to use. if this image does not exists, the build will fail
* The source for the code to be deployed: a git repository, S3, or a Docker image tarball in Google Cloud Storage (`gcs_docker`).
* environment configuration like **nginx_conf** telling the creator how to configure the instance in the infrastructure.
* Health check settings - if the service supports health checking, these will follow that section.

File format
---
The service file format (typically called `service.yml`) is the [yml format](http://docs.ansible.com/ansible/YAMLSyntax.html). Sections and all sections parameters are to be typed in lower case.

Service file explained
-------
#### The `machine` section
* `image` - the packer image.
* `start` - the command require to start the service, e.g `npm start`
* `daemon_type` - this depends on the Ubuntu installation. currently only `upstart` is supported, `system.d` will be added.
* `install` - command collection that required in order to setup the code in the machine. For node project this typically includes `npm install`, but any setup instruction can be performed like creating folder, files and so on.
<br>**important!** <br>All the commands under the install section will be performed under the same user, which is **not** the root user. if you need system configuration, use packer.
* `environment_variables` - typically used in the override section since each environment usually use it's own set. This is an array representing entries that will be available to the process as system variables.<br>
**Important!**<br>
Do not include any secret information in the service file. Any and all secret environment variables should be set through the vault servers. if you need to set a secure parameter (db password, and access key and so on), please add them using Jenkins `set-vault-var` job. you can use `show_vault_variables` to ascertain your variables are set for the right environment.
* `instance_type` - the [aws ec2 instance](https://aws.amazon.com/ec2/instance-types/) type. This will be defaulted to the environment value if not provided.

#### The `deployment` section
* `service_name` - the service name to be setup in the machine. should be the project name.
* `source` - deployment origin. Supported `type` values: `git`, `s3`, `gcs_docker`, and `nop` (no code load). Each type has its own settings:
  * `git`
    * `repo` - full git link to the repo e.g `git@github.com:Betterez/betterez-app.git`. Note again, this is the git url, **not** the HTTP one!
    * branch_name which branch to pull, most of the time it will be `master`, for overriding please follow the overriding section.
  * `s3`
    * `bucket` - the S3 bucket from which the installer can pull the image.
    * file_name file name to extract
  * `gcs_docker` - Docker image exported with `docker save` and uploaded to Google Cloud Storage as a tarball. Used when the service runs as a container instead of cloned source code. **Required fields:** `bucket` and `dir_name` (the deploy fails if either is missing).
    * `bucket` - GCS bucket name.
    * `dir_name` - prefix of the “folder” in the bucket (e.g. `builds/` or `bpes-java/builds/`). Use a trailing slash when possible. The deploy selects the **most recently updated** object under that prefix whose name ends in `.tar` or `.tar.gz`, then renames it to **`image.tar`** on the instance at `/home/bz-app/<service_name>/image.tar` (fixed name in code; the object name in GCS can be anything).
    * **Deploy flow** — (1) the Jenkins/automation runner lists objects under `dir_name`, picks the latest `.tar`/`.tar.gz`, downloads and renames to `image.tar`; (2) uploads it to the instance at `/home/ubuntu/image.tar`; (3) moves it to `/home/bz-app/<service_name>/`; (4) `machine.install` runs from that directory (`docker load -i image.tar`); (5) `machine.start` runs the container. Unlike `s3`, the tarball is **not** extracted with `tar` — it is loaded with Docker.
    * **Runner credentials** — the automation host (not the EC2 instance) must authenticate to GCS. Set JSON with project id and credentials in settings folder of a GCP service account JSON key with read access to the bucket.
    * **AMI requirements** — Docker must be installed on the packer image. The `bz-app` user needs permission to run Docker (e.g. member of the `docker` group), unless `machine.start` uses `sudo`.
    * **Healthcheck** — for a co-hosted sidecar (Java container + Node facade), set `healthcheck.perform: false` on the Docker app so provisioning waits only on the primary HTTP service.
    * **CI** — upload any `.tar`/`.tar.gz` under `dir_name` (e.g. `builds/build_42.tar.gz`); the deploy always normalizes to `image.tar` on the server.
  * `nop` - skip source loading; useful only when `machine.install` / `machine.start` do not depend on cloned or downloaded artifacts (rare).
* `service_type` - use to determent installing behavior:
  * `http` - Most popular one, this one determine that the service is an http service that can be balanced
  * `socket` - a service that using sockets directly and can not be balanced by a load balancer
  * `worker` - a service that performs background tasks (e.g. reports) and it's interfacing is not relevant
* `nginx_conf` - This goes to the load balancing scheme for that project. should be one of the following:
  * `app` - for an application extension
  * `api` - for api servers
  * `worker` - for worker server
* `path_name` - for application usage, the load balancing path to use.
  * `/` - this is for the default application.
  * any other path (e.g `cart`) - a single legal url part (no spaces or special characters, all lower case)<br>
  if a path_name of *'cart'* was used, then the application would be forward calls to [app_domain]/cart.
* `healthcheck` - parameters on how and if to perform a health check:
  * `perform` - `true` / `false` (only!) if a service does not require a healthcheck this should be `false`. Otherwise (most cases) it should be `true`.
  * `command` - command requires to perform a health check. the output from that command will be used to determine if the service is healthy
  * `result` - partial excerpt from the output of the healthcheck command. This excerpt can be in any part of the output. as long as it's there, the service considered to be healthy.
* `elb_version` - if not present or 1, use the classic elb. if 2, use the new elb and the instance will be inserted into the respected target group.

#### Multiple applications on one instance (`applications`)

Optional root-level `applications` (array) allows several services on the same EC2 instance. Each element has its own **`deployment`** and **`machine`** (same keys as the single-app layout): git clone, S3 deploy, or `gcs_docker` image load, `install` / `fast_install`, `daemon_type`, `start`, optional Vault/Secrets Manager via `service_name`, and its own systemd or upstart unit.

* **Order** — Array order defines clone and install order. Put dependencies first (for example an internal service before the facade that calls it).
* **Backward compatibility** — If `applications` is omitted, the file behaves as before using only the root `deployment` and `machine` sections.
* **Infrastructure primary** — The EC2 tag `Repository`, ELB-related lookups, and the root `deployment` / merged `machine` used after load follow this rule: the **last** application whose `healthcheck.perform` is `true`; if none are `true`, the **last** application in the list. Only apps with `healthcheck.perform: true` are waited on during instance health checks; set it to `false` for sidecars that should not block provisioning. (VER)
* **Shared `machine` keys** — You can keep shared values (for example `image`, `servers_count`, `instance_type`) on the root `machine` section. They are merged with the primary app’s `machine` when the file is loaded so AMI selection and defaults still work.
* **Overrides** — Because `applications` is a list, an environment override usually replaces the whole `applications` array for that environment unless you repeat the full list under `override.<env>.applications`.

Abbreviated example:

```yaml
machine:
  image: my-packer-image
applications:
  - deployment:
      service_name: internal-api
      healthcheck: { perform: false, command: "", result: "" }
      source: { type: git, repo: git@bitbucket.org:org/repo.git, branch_name: main }
    machine: { daemon_type: systemd, start: "npm start", install: ["npm ci"] }
  - deployment:
      service_name: facade-api
      healthcheck: { perform: true, command: "curl -m 5 -i localhost:3000/health|head -n1", result: "200 OK" }
      nginx_conf: api
      path_name: api
      service_type: http
      source: { type: git, repo: git@github.com:Betterez/facade.git, branch_name: master }
      elb_version: 2
    machine: { daemon_type: systemd, start: "npm start", install: ["npm ci"] }
```

The AMI or base image must include SSH access (and `known_hosts`) for every git host used (for example both GitHub and Bitbucket). For `gcs_docker` apps, the AMI must also include Docker.

#### Co-hosted Docker + git example

```yaml
machine:
  image: node24130_arm64_java11_nginx1280_moreheader_wazuh411_cis112_rsyslog_20_alloy_181v2_ib
  instance_type: t4g.small
applications:
  - deployment:
      service_name: btrz-api-bpes-java
      healthcheck:
        perform: false
      source:
        type: gcs_docker
        bucket: buson-bpe-builds
        dir_name: builds/
    machine:
      daemon_type: systemd
      install:
        - docker load -i image.tar
      start: >
        /usr/bin/docker run --rm --name btrz-api-bpes-java
        --env-file /home/bz-app/.env
        -p 8082:8082

  - deployment:
      service_name: btrz-api-bpes
      healthcheck:
        command: curl -m 5 -i localhost:3000/healthcheck|head -n1
        perform: true
        result: 200 OK
      nginx_conf: api
      elb_version: 2
      path_name: bpes
      service_type: http
      source:
        type: git
        repo: git@github.com:Betterez/btrz-api-bpes.git
        branch_name: main
    machine:
      daemon_type: systemd
      start: /usr/bin/npm --prefix /home/bz-app/btrz-api-bpes start
      install:
        - npm install --no-package-lock
```

In this layout the Java container is deployed from GCS (`healthcheck.perform: false`); the Node API is the infrastructure primary (ELB, nginx, health wait). The latest `.tar` under `dir_name` is always saved as `/home/bz-app/btrz-api-bpes-java/image.tar`, so `docker load -i image.tar` in `machine.install` is correct regardless of the object name in GCS.

### Overriding
It is possible to override any of the above sections using the `override` section. While this section is not required, it can be used to set different options for different environments (staging, sandbox and so on).
#### Settings up overrides
if an override is required, the `override` section need to be present, with a sub section for the environment required. Then, the full tree including the override. e.g. overriding the image parameter, for the staging environment:
```yaml
machine:
  image:  connex-test-1
  start:  "./connex2"
  daemon_type:  upstart
  install:
deployment:
  service_name: "connex2"
  source:
    type: s3
    bucket: "betterez-connex2"
    file_name: connex2
  service_type: "http"
  nginx_conf: "connex"
  path_name:  "connex"
  healthcheck:
    perform: true
    command: "curl -m 5 -i localhost:22000/healthcheck|head -n1"
    result: "200 OK"
override:
  staging:
    machine:
      image:  connex-test2
```
In this example the image to be used is the `connex-test-1` image. This image will be used everywhere (sandbox, production) but if the *staging* environment will be used, then the `connex-test2` image will be used instead.
**ANY** value can be overridden. Here is another example:
```yaml
override:
  staging:
    deployment:
      source:
        branch_name: staging
    machine:
      environment_variables:
        - "NODE_ENV=staging"
        - "location=aws"
  staging2016:
    deployment:
      source:
        branch_name: staging
    machine:
      environment_variables:
        - "NODE_ENV=staging2016"
        - "location=aws"
  sandbox:
    deployment:
      source:
        branch_name: sandbox
    machine:
      environment_variables:
        - "NODE_ENV=sandbox"
        - "location=aws"
  production:
    deployment:
      source:
        branch_name: production
    machine:
      environment_variables:
        - "NODE_ENV=production"
        - "location=aws"
```
This excerpt shows the usage of overriding the `environment_variables` section, probably the one that will be override the most. In this example we're overriding the `NODE_ENV` parameter.

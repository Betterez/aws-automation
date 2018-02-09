About service files
=============
Every machine project(a project that requires a machine to run on, unlike mobile or automation) will typically includes a service file, describing:
* The type of machine required - this will be the packer image for the server creator to use. if this image does not exists, the build will fail
* The source for the code to be deployed: either S3 or a git repository.
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
* `source` - currently git or S3. each of those have there own settings:
  * `git`
    * `repo` - full git link to the repo e.g `git@github.com:Betterez/betterez-app.git`. Note again, this is the git url, **not** the HTTP one!
    * branch_name which branch to pull, most of the time it will be `master`, for overriding please follow the overriding section.
  * `s3`
    * `bucket` - the S3 bucket from which the installer can pull the image.
    * file_name file name to extract
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

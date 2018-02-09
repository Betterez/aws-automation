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
* `--branch` - the branch name in case of a git repo. default to `master`.

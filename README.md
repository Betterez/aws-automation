This is an amazon sdk repo used currently for ecs.

Required native libraries
----------------------------
1. ruby-all-dev
2. zlib1g-dev zip
3. build-essential


Required libraries
------------------
1. aws-sdk
2. net-ssh -v 2.9.3.beta1 (in windows) or  net-ssh (unix)
3. net-scp
4. nokogiri
5. mixlib-shellout
6. redis
7. rubocop - is a good choice for reformatting. not a must.

Documentation
-------------
You can generate documentation by running "rdoc" at the root directory for this repo, at the root and viewing index.html.

Required files under settings folder
------------------------------------
1. you will need to create an authentication.json file with the secret key data for this project to work.
2. you need a setting.json specific to the environment you're working in.

Testing
--------
Running all tests is simple, `ruby test/test_all.rb`
You can also run a specific test by using it's own file name.
If you're writing a test, make sure to include it in the `test_all.rb`.
It is also possible to run an informative test with the `-v` tag at the end.

Scripts
---------
Scripts are mentions [here](wiki/scripts.md).

How to write a service file
----------------
service file explained [here](wiki/service_files.md).
How to setup your infrastructure explained [here](wiki/infrastructure.md).

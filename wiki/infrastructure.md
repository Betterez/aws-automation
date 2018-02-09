Settings infrastructure
=========================
In order to set up an environment for a project (the script file described [here](scripts.md) ).
You need to set either a classic ELB or an ALB with a target group.

Tagging
-----------
In order to deploy the correct instance to the target group/classic ELB (will be referred to destination from now), the destination needs to be tagged properly.

#### Hereby are the tags and the service equivalents:
|Destination|Service tag|   Meaning        |
|-----------|-----------|          ------- |
|Elb-Type   |nginx_conf |family type for that destination - this can be any value |
|Environment|N/A|Specify which environment this destination belongs to|
|Path-Name  |path_name  |The path name for the application. root applications use `/`, other uses there own (`cart`)|
|Release|N/A|Will this destination receive new instances. In production, this first goes to the testing account. in boxing, instances go directly to the destination

* Names are case sensitive

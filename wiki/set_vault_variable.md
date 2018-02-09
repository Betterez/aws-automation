How to set a vault variable
====================================
File name: `update_vault.rb`
----------------------------------
### options:
* --repo the repository name to set the variable format
* --env - the environment to set it format
* --vars - strings of variable(s) to set in a form of `name1=value1,name2=value2` and so on
* --append - **critical**, if not set, will remove **all** variables and place only the new ones. if set will leave all the current ones and only set or update the ones noted

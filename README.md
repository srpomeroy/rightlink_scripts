RightLink Scripts
=================

RightScripts for RightScale's RightLink10 (aka RightLinkLite) agent used in the
Base ServerTemplate and beyond.

This repository contains the collection of RightScrits used in ServerTemplates that go with
the new RightLink10 agent. The scripts for the base ServerTemplate are in the rll subdirectory.

How it Works
------------

This repository masquerades to RightScale as a Chef Cookbook repository but everything here
really are RightScripts, i.e. shell scripts that are executed by the RightScale agent.

The directory structure is kept very simple: each directory of the root contains a collection
of scripts and masquerades as a Chef cookbook. Each such directory contains a set of bash or
ruby scripts (or powershell in the case of Windows) and a Chef metadata.rb file that describes
the scripts as well as the inputs of each on (or attributes in Chef terminology).

Within the RightScale dashboard these scripts can be composed just like Chef recipes and they
will be executed by RightLink 10 (aka RightLinkLite) just like RightScripts. The inputs are
passed via environment variables, therefore their names should be kept flat and, by convention,
in all caps. The input values must be simple strings.

In terms of naming, in order to associate a file with a recipe name RightLink searches for the
first file that matches `recipename.*` and that is executable, thus you are free to add `.sh`,
`.rb`, or `.ps1` extensions. (However, ensure your editor doesn't save backup files by adding
a `~` or `.bak` at the end of filenames.)

Developer Info
--------------

In order to modify a script in this repo the recommended first steps are:
- Fork the repo on github
- Clone the fork to your laptop
- Create a branch (or use master, your choice)
- Make a change, git commit the change,
- Set the RS_KEY environment variable to your OAuth key for your account (found in the RS dashboard
  on the `settings>API credentials` page
- Use `./push` to push to github and RightScale, this creates a repository in RS named
  `rightlink_scripts_<your_branch_name>` and makes RS fetch from github
- Ensure you have imported the official _RL10.0.X Linux Base_ ServerTemplate to your
  account (for the right _X_)
- Run `./make_st -base 'RL10.0.X Linux Base' -clone` to clone the official base ServerTemplate
  and have it changed to use your repository
- In the RightScale dashboard, find your ST, create a server from it, and launch it, it now
  uses your modified scripts

For a faster edit&test cycle, you can further clone the git repo onto your server and edit & test
locally on the server as follows:
- SSH to the server and clone your git repo to your home directory or wherever is convenient
- Tell RL10 where to find your cookbook(s), specifically, you need to point RL10 to the directory
  that has your cookbooks as subdirectories. Assuming you cloned the rightlink_scripts repo
  into `/home/rightscale/rightlink_scripts` this would be as follows:
  (_warning, these instructions are incomplete_)
```
. /var/run/rll-secret
curl -X POST http://localhost:$RS_RLL_PORT/rll/.....
```
  This now means that RL10 expects to find an operational script called `rll::init` in the
  dashboard at `/home/rightscale/rightlink_scripts/rll/init.*`
- Test your scripts by running them fro mthe dashboard or command line using
```
curl ...
```
- When done, you can `git commit` your changes and push them using the `./push` script, which
  will ensure that the RS platform refetches the respository.
- Note that if you need to clone multiple repos onto your server you cannot tell RL10 to search
  more than one repo for scripts. A work-around is to create a separate directory for RLL that
  contains symlinks to all the cookbook directories you want RL10 to search.
- To troubleshoot the process use the RightLink log audit entry on your server, RL10 logs
  the steps to download cookbooks and then search for the appropriate scripts.

License
-------
See [![MIT License](http://img.shields.io/:license-mit-blue.svg)](LICENSE)

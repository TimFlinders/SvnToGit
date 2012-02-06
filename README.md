# SvnToGit

## What is this?

svn2git converts a Subversion repository into a git repository. It
uses git-svn to do the bulk of the conversion, but does a little extra
work to convert the SVN way of doing things into the git way.

Specifically, svn2git can be useful in the case where the SVN repo
you're converting did not start out as having a conventional
trunk/branches/tags structure, but was moved over at a specific
revision in the history.

## How do I use it?

This isn't quite available as a module on CPAN yet, so for the moment, you'll
have to clone this repo.

In order to make the Git conversion process faster, the first thing you need to
do is clone the SVN repo you want to convert to some local location:

    /path/to/SvnToGit/bin/svn2git setup svn://path/to/your/svn/repo /path/to/local/svn/repo

This creates an SVN repo at /path/to/local/svn/repo. You'll then want to
generate an authors file, which you can do by following [these instructions][1].
Now you can convert the repo. If your repo doesn't have any history issues, then
you can convert it normally:

    /path/to/SvnToGit/bin/svn2git convert /path/to/local/svn/repo /path/to/local/git/repo --authors-file /path/to/authors/file

If there was a point where the trunk/tags/branches was introduced, though,
you'll want to specify that:

    /path/to/SvnToGit/bin/svn2git convert /path/to/local/svn/repo /path/to/local/git/repo --authors-file /path/to/authors/file --start-std-layout-at 5

In this case, the SVN repo is split into two repos which are converted
separately and then stitched together at the end. Unfortunately the program
isn't smart enough to figure out exactly how to do this, so you'll need to graft
them together yourself (you'll be given instructions on how to do this when the
time comes, though, so don't worry). And then sit back and let the magic happen.
You'll probably want to inspect the resulting Git repo. If it didn't work
correctly, then you are free to re-run the `convert` command again.

See `svn2git --help` for more help on which options you can pass.

## I found a bug! or, I have a feature request!

Great! Please file any issues in [Issues][2].

## Can I contribute, and if so, how do I do so?

Yes, I will be happy to accept any patches that you give me. Pull down the code,
make a branch, and send me a pull request, and I'll get back to you.

## Who made this?

This project is (c) 2010-2012 Elliot Winkler. If you have any questions, please
feel free to contact me through these channels:

* **Twitter**: [@mcmire](http://twitter.com/mcmire)
* **Email**: <elliot.winkler@gmail.com>

Or, just PM me through Github.

## Can I use this in my personal/commercial project?

Yes, you are free to do whatever you like with this code. If you do use it, an
attached courtesy would be appreciated. The only other thing I ask is that you
make the world a better place with your awesome code powers!

[1]: http://technicalpickles.com/posts/creating-a-svn-authorsfile-when-migrating-from-subversion-to-git/
[2]: http://github.com/mcmire/SvnToGit/issues

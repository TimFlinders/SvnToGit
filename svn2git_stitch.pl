#!/usr/bin/perl -w
#
# Author: Elliot Winkler
# Last updated: 31 Jan 2010
#
# Adapted from http://justatheory.com/computers/vcs/git/bricolage-migration/stitch
# See http://justatheory.com/computers/vcs/git/
#

=head1 NAME

svn2git_stitch.pl - Convert a SVN repo with a late-introduced
conventional directory structure to Git

=head1 SYNOPSIS

  svn2git_stitch.pl --start-of-new-structure REV [OPTIONS] SVN_URL [NEW_REPO_DIR]
  
  OPTIONS:
    --end-of-old-structure REV
    --grafts-file FILE
    --final-git-url GIT_URL
    --authors AUTHORS_FILE, --authors-file AUTHORS_FILE
    --clear-cache
    --verbose, -V
    
=cut

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use File::Spec::Functions qw(rel2abs file_name_is_absolute);
use File::Basename;
use Term::ANSIColor;

use lib dirname(__FILE__);
use SvnToGit;

my %ARGV;
my($svn_url, $final_repo);

my($cached_pre_repo, $cached_post_repo) = ("/tmp/git.pre.cached", "/tmp/git.post.cached");
my($pre_repo, $post_repo) = ("/tmp/git.pre", "/tmp/git.post");
my(@pre_local_branches, @pre_remote_branches);
my(@post_local_branches, @post_remote_branches);
my(@final_local_branches, @final_remote_branches);

#---

sub run {
  print colored("@_\n", "yellow") if $ARGV{verbose};
  system @_;

  my $exit = $? >> 8;
  die "@_ exited with $exit" if $exit;

  return 1;
}

sub cd {
  my $dir = shift;
  chdir $dir;
  my $cwd = get_cwd();
  info("Current directory: $cwd");
}
sub get_cwd {
  my $cwd = `pwd`;
  chomp $cwd;
  $cwd;
}

sub header {
  my $msg = shift;
  print colored("\n##### $msg #####\n\n", "cyan");
}
sub info {
  my $msg = shift;
  print colored("$msg\n", "green");
}

sub get_local_branches {
  my @branches = map { s/^\s*\*\s*//; s/^\s+//; s/\s+$//; $_ } `git branch`;
  # bypass pointers
  @branches = map { /^([^ ]+) ->/ ? $1 : $_ } @branches;
  info("Local branches: " . join(", ", @branches)); 
  @branches;
}
sub get_remote_branches {
  my @branches = grep { !/HEAD/ } map { s/^\s+//; s/\s+$//; $_ } `git branch -r`;
  # bypass pointers
  @branches = map { /^([^ ]+) ->/ ? $1 : $_ } @branches;
  info("Remote branches: " . join(", ", @branches));
  @branches;
}

#---

sub process_command_line {
  my %opts;
  GetOptions(
    \%opts,
    "grafts-file=s",
    "end-of-old-structure=i",
    "start-of-new-structure=i",
    "authors-file|authors=s",
    "final-git-url=s",
    "clear-cache",
    "verbose|v",
    "quiet|q",
    "help|h"
  ) or pod2usage(2);
  pod2usage(1) if $opts{help};
  
  # convert --foo-bar to $ARGV{foo_bar}
  for my $k (keys %opts) {
    my $v = $opts{$k};
    $k =~ s/-/_/g;
    $ARGV{$k} = $v;
  }
  
  pod2usage(2) unless length(@ARGV) >= 1;
  
  unless ($ARGV{start_of_new_structure}) {
    print STDERR "--start-of-new-structure is a required option\n";
    pod2usage(2);
  }
  $ARGV{end_of_old_structure} ||= $ARGV{start_of_new_structure} - 1;
  
  $ARGV{final_git_url} ||= 'ssh://you@yourserver.com/path/to/git/repo';
  if ($ARGV{grafts_file}) {
    $ARGV{grafts_file} = rel2abs($ARGV{grafts_file}) unless file_name_is_absolute($ARGV{grafts_file});
  } else {
    $ARGV{stop_at_grafting} = 1;
  }
  $ARGV{quiet_option} = $ARGV{quiet} ? "--quiet" : "";
  
  ($svn_url, $final_repo) = @ARGV;
  $final_repo ||= basename($svn_url) . ".git";
  $final_repo = rel2abs($final_repo) unless file_name_is_absolute($final_repo);
}

sub main {
  svn2git();
  work_on_pre();
  work_on_final();
  
  my $final_repo_name = basename($final_repo, '.git') . '.git';
  print <<EOT
  
----
Conversion complete! Now ssh into your server and run something like this:

  su git
  cd /path/to/git/repos
  mkdir $final_repo_name
  cd $final_repo_name
  git init --bare
  # Thanks <https://kerneltrap.org/mailarchive/git/2008/10/9/3569854/thread>
  git config core.sharedrepository 1
  chmod -R o-rwx .
  chmod -R g=u .
  find . -type d | xargs chmod g+s

The newly converted Git repo is available at $final_repo. To upload
it to your server, simply run:

  cd $final_repo
  git push origin --all
  
EOT
}

#---

sub svn2git {
  header "Running SVN repo through svn2git";
  
  if ($ARGV{clear_cache} || !(-e $cached_pre_repo && -e $cached_post_repo)) {
    run qw(rm -rf), $cached_pre_repo, $cached_post_repo;
    SvnToGit->convert(
      svn_repo => $svn_url,
      git_repo => $cached_pre_repo,
      root_is_trunk => 1,
      revisions => "1:$ARGV{end_of_old_structure}",
      authors_file => $ARGV{authors_file},
      verbose => $ARGV{verbose}
    );
    SvnToGit->convert(
      svn_repo => $svn_url,
      git_repo => $cached_post_repo,
      revisions => "$ARGV{start_of_new_structure}:HEAD",
      authors_file => $ARGV{authors_file},
      verbose => $ARGV{verbose}
    );
  }
  run qw(rm -rf), $pre_repo, $post_repo;
  run "cp", "-r", $cached_pre_repo, $pre_repo;
  run "cp", "-r", $cached_post_repo, $post_repo;
}

sub work_on_pre {
  copy_commits_from_post_to_pre();
  transfer_remote_branches_to_local_branches();
  
  if ($ARGV{stop_at_grafting}) {
    print <<EOT;
    
----
Okay! The first and second half of the SVN repo have been converted,
but you still need to graft them together.

Next steps:

1. Take a look at /tmp/git.pre and /tmp/git.post to find the commit ids
   where the "pre-repo" starts and the "post-repo" ends
2. Create a graft file that will connect pre-repo to post-repo. It will
   look like this:
  
     <start of pre-repo id> <end of post-repo id>
    
   You can read more about grafting here:
  
     http://git.wiki.kernel.org/index.php/GraftPoint
    
3. Tell this script about the graft file with the --grafts-file option

EOT
    exit;
  }
  
  graft_pre_and_post();
  clone_pre();
}

sub work_on_final {
  transfer_remote_branches_to_local_branches(move => 1);
  relocate_master();
  cleanup();
}

#---

sub copy_commits_from_post_to_pre {
  header "Copy commits from post repo to pre";
  
  cd $post_repo;
  # Note that this doesn't contain master for some reason
  @post_remote_branches = get_remote_branches();
  
  cd $pre_repo;
  # Transfer objects from the post repo to the pre repo
  # This doesn't work when we say git fetch --tags for some reason?
  run qw(git fetch), $post_repo;
  # Save post's master (which is, conveniently, saved to FETCH_HEAD)
  # because we're going to need it later when we re-point master
  run qw(git branch post-master FETCH_HEAD);
  # Transfer remote branches from post too
  for my $branch (@post_remote_branches) {
    run qw(git fetch), $post_repo, "refs/remotes/$branch:refs/remotes/$branch";
  }
}

sub transfer_remote_branches_to_local_branches {
  my %opts = @_;
  
  # We've got the remote branches copied over, but we still have to get them locally
  
  header(($opts{move} ? "Moving" : "Copying") . " remote branches to local ones");
  
  # Note that this doesn't contain master, because pre's remote branches didn't contain master
  @pre_remote_branches = get_remote_branches();
  
  for my $remote (@pre_remote_branches) {
    (my $local = $remote) =~ s{origin/}{};
    unless ($local eq "master") {
      run qw(git branch $ARGV{quiet_option} --no-track), $local, "refs/remotes/$remote";
      run qw(git branch $ARGV{quiet_option} -r -D), $remote if $opts{move};
    }
  }
}

sub graft_pre_and_post {
  header "Grafting pre and post repos";
  
  system "cp", $ARGV{grafts_file}, ".git/info/grafts";
  run qw(git checkout $ARGV{quiet_option} master);
  run qw(git filter-branch $ARGV{quiet_option} --tag-name-filter cat -- --all);
  unlink ".git/info/grafts";
}

sub clone_pre {
  # Clone pre to remove duplicate commits
  # Note that we're cloning to the final location now
  header "Cloning pre to remove duplicate commits";
  cd "..";
  run "rm", "-rf", $final_repo;
  run "git", "clone", $ARGV{quiet_option}, "file://$pre_repo", $final_repo;
  cd $final_repo;
}

sub relocate_master {
  # Remember when we saved post's master branch?
  # Here's where we save it as the new master.
  
  header "Relocating master";
  run qw(git checkout $ARGV{quiet_option} post-master);
  run qw(git branch $ARGV{quiet_option} -D master);
  run qw(git checkout $ARGV{quiet_option} -b master);
  run qw(git branch $ARGV{quiet_option} -D post-master);
}

sub cleanup {
  header "Cleaning up";
  run qw(git remote rm origin);
  run qw(git remote add origin), $ARGV{final_git_url};
  run qw(git gc $ARGV{quiet_option});
  run qw(git repack $ARGV{quiet_option} -a -d -f --depth 50 --window 50);
}

#---

process_command_line();
main();

#---

=head1 DESCRIPTION

svn2git_stitch.pl can be used to convert an SVN repository where the
conventional directory structure (trunk, branches, tags) was
introduced not from the beginning but from some point perhaps in the
middle, retaining history both before the split and afterward. It does
this by running the half of the SVN repo before the split and the half
after the split through svn2git separately and then grafting the two
halves together.

=head1 USAGE

First, you'll need my fork of svn2git, SvnToGit.pm, which you should
be able to find alongside this script on Github. Just place it in the
same folder where you downloaded this script (I may put it on CPAN
at some point).

The first time you run this script, it will automatically stop after
the two halves of the SVN repo are converted but right before grafting
them together. This is because you will need will need the Git commit
ids representing the end of the first half and the start of the second
half in order to connect the two. The two repos are saved to
C</tmp/git.pre> and C</tmp/git.post>, and you can inspect them from
the command line or using a tool such as GitX (Mac) or TortoiseGit
(Windows). Once you have the commit ids, put them in a graft file
(read more about them
L<<a href="http://git.wiki.kernel.org/index.php/GraftPoint">here</a>>).
Then, tell the script to use it by re-running it with the --grafts-file
option.

=head2 Required options

=head3 --start-of-new-structure REV

Since this script doesn't know which revision your SVN repo switched
over to a conventional structure, you have to tell it. This is where
you do that.

=head2 Options

=head3 --end-of-old-structure REV

By default, everything between revision 1 up to (but not including)
start-of-new-structure will be treated as the first half, and everything
from start-of-new-structure onward will be treated as the second half.

However, if your SVN repo contains unnecessary commits where the new
structure was introduced and you do not wish to carry those over to
the new git repo, you may specify the revision at which the first half
ends.

=head3 --grafts-file FILE

The file path that points to the grafts file used to stitch together
the two repos. Copied to C<.git/info/grafts> in the final repository.

=head3 --authors AUTHORS_FILE

=head3 --authors-file AUTHORS_FILE

The file that maps SVN committers to Git committers. This will be
passed straight to C<svn2git>.

=head3 --final-git-url GIT_URL

The URL to the Git repository on your server to which you will push
your newly converted repo. This will be added as a remote in the final
step of the conversion so that C<git push> works out of the gate.

=head3 --clear-cache

The first time this script is run, the Git versions of the two halves
of the SVN repo are cached so that you do not have to go through the
process of converting them if you run the script again (since it may
take a long time depending on the size of your original repo). This
option will allow you to regenerate these Git repos should you ever
need to do so.

=head3 --verbose

=head3 -V

Prints commands as they are executed, as well as directories which are
changed.

=head3 --help

=head3 -h

You can probably guess what this does.

=head1 SEE ALSO

=over 4

=item *
L<<a href="http://blog.lostincode.net/archives/2010/01/31/git-svn-stitching">My
writeup about how I wrote this script</a>>

=item *
L<<a href="http://justatheory.com/computers/vcs/git/">David Wheeler's
stitch script upon which this was based</a>>

=item *
L<<a href="http://git.wiki.kernel.org/index.php/GraftPoint">Article
about grafts on the community Git wiki</a>>

=head1 AUTHOR/LICENSE

(c) 2010 Elliot Winkler. Released under the MIT license.

=cut
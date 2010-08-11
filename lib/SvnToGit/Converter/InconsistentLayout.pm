#!/usr/bin/env perl

package SvnToGit::Converter::InconsistentLayout;

# Need to re-use all these modules?
use Modern::Perl;
use File::Basename;
use File::Spec::Functions qw(rel2abs file_name_is_absolute);
use Data::Dumper::Again;
use Data::Dumper::Simple;
my $dd = Data::Dumper::Again->new(deepcopy => 1, quotekeys => 1);
my $tdd = Data::Dumper::Again->new(deepcopy => 1, quotekeys => 1, terse => 1, indent => 0);

#use lib dirname(__FILE__) . "/..";
#use SvnToGit::Converter;
use parent 'SvnToGit::Converter';

our $cached_pre_repo_path  = "/tmp/git.pre.cached";
our $cached_post_repo_path = "/tmp/git.post.cached";
our $pre_repo_path         = "/tmp/git.pre";
our $post_repo_path        = "/tmp/git.post";

sub new {
  my($class, %data) = @_;
  %data = $class->buildargs(%data);
  bless \%data, $class;
}

# Not documented.
# This is used by new() to make a default list of options.
#
sub buildargs {
  my($class, %data) = @_;
  
  %data = $class->SUPER::buildargs(%data);

  $data{end_root_only_at} ||= $data{start_std_layout_at} - 1;
  
  $data{final_git_url} ||= 'ssh://you@yourserver.com/path/to/git/repo';
  
  if ($data{grafts_file}) {
    $data{grafts_file} = rel2abs($data{grafts_file}) unless file_name_is_absolute($data{grafts_file});
  } else {
    $data{stop_at_grafting} = 1;
  }
  
  return %data;
}

=head2 $converter-E<gt>run

Since we're converting a repo with an inconsistent structure, the
process is a bit more involved than just the normal way:

=over 4

=item *

Use git-svn to clone the two parts of the SVN repo separately such
there are two repos (note that the C<clone> option here has no effect
since it's kind of pointless)

=item *

Use C<git fetch> to copy commits (including branches and tags) from
the second repo to the first repo

=item *

Re-check out remote branches as local branches in the first repo

=item *

Graft the second repo onto the end of the first repo

=item *

Fix master so it points to the end of the second repo instead of the
first

=item *

Perform optimizations on the final repo to reduce file size

=back

=cut

sub run {
  my $self = shift;
  
  $self->ensure_git_present();

  $self->clone_or_load_halves();
  
  $self->load_cached_repos();
  $self->copy_commits_from_post_to_pre();
  #$self->transfer_remote_branches_to_local_branches(
  #  remote_branches => $self->{pre_repo}->{remote_branches}
  #);
  if ($self->{stop_at_grafting}) {
    print $self->graft_message if $self->{verbosity_level} > 0;
    return;
  }
  $self->graft_pre_and_post();
  #$self->clone_pre();
  
  $self->cache_branches_and_tags();
  $self->move_remote_branches_to_local_branches();
  $self->relocate_master();
  $self->optimize_repo();
  
  print $self->final_message if $self->{verbosity_level} > 0;
  
  #$self->cmd("rm", "-rf", $cached_pre_repo_path, $cached_post_repo_path, $pre_repo_path, $post_repo_path);
}

sub clone_or_load_halves {
  my $self = shift;
  
  my $do_clone = ($self->{clear_cache} || !(-e $pre_repo_path && -e $post_repo_path));
  
  unless ($do_clone) {
    $self->info("Not cloning halves since we've already done that.");
  }
  
  my $start_rev = $self->{revisions}->[0] || 1;
  my $end_rev = $self->{revisions}->[1] || "HEAD";
  
  if ($do_clone) {
    $self->header(sprintf('Cloning %s-%s of the SVN repo to create the first git repo...', $start_rev, $self->{end_root_only_at}));
  }
  my $pre = $self->{pre_repo} = SvnToGit::Converter::ConsistentLayout->new(
    svn_repo => $self->{svn_repo},
    git_repo => $cached_pre_repo_path,
    authors_file => $self->{authors_file},
    root_only => 1,
    revisions => [$start_rev, $self->{end_root_only_at}],
    force => 1,
    verbosity_level => $self->{verbosity_level}
  );
  if ($do_clone) {
    $pre->clone();
    $pre->fix_branches_and_tags();
  } else {
    $pre->cache_branches_and_tags();
  }
  
  if ($do_clone) {
    $self->header(sprintf('Cloning %s-%s to create the second repo...', $self->{start_std_layout_at}, $end_rev));
  }
  my $post = $self->{post_repo} = SvnToGit::Converter::ConsistentLayout->new(
    svn_repo => $self->{svn_repo},
    git_repo => $cached_post_repo_path,
    authors_file => $self->{authors_file},
    revisions => [$self->{start_std_layout_at}, $end_rev],
    force => 1,
    verbosity_level => $self->{verbosity_level}
  );
  if ($do_clone) {
    $post->clone();
    $post->fix_branches_and_tags();
  } else {
    $post->cache_branches_and_tags();
  }
}

sub load_cached_repos {
  my $self = shift;
  $self->cmd("rm", "-rf", $pre_repo_path, $post_repo_path);
  $self->cmd("cp", "-r", $cached_pre_repo_path, $pre_repo_path);
  $self->cmd("cp", "-r", $cached_post_repo_path, $post_repo_path);
}

sub cache_branches_and_tags {
  my($self, $where) = @_;
  #my $info = $self->get_branches_and_tags(($where eq "final") ? $self->{git_repo} : $self->{"${where}_repo_path"});
  #$self->{"#{where}_${_}"} = $info->{$_} for %$info;
  my $info = $self->get_branches_and_tags();
  $self->{"final_${_}"} = $info->{$_} for %$info;
}

sub copy_commits_from_post_to_pre {
  my $self = shift;
  
  $self->header("Copying commits from the second repo to the first...");
  
  $self->chdir($pre_repo_path);
  
  # Transfer objects from the post repo to the pre repo.
  # (This no longer does anything by default in git 1.7 (for some reason),
  # so we have to tell it which branch to pull.)
  # Notice that we're putting post's master branch in a new branch.
  # This will come in handy later when we graft the two repos together at the end.
  $self->git("fetch", $post_repo_path, "master:post-master");  # XXX: Does this work if we say git fetch --tags?
  
  # Transfer remote branches from post too
  for my $branch (@{$self->{post_repo}->{remote_branches}}) {
    $self->git("fetch", $post_repo_path, "refs/remotes/$branch:refs/remotes/$branch");
  }
}

sub move_remote_branches_to_local_branches {
  my $self = shift;
  
  # We've got the remote branches copied over, but we still have to get them locally
  
  $self->header("Moving remote branches to local ones...");
  
  for my $remote (@{$self->{final_remote_branches}}) {
    (my $local = $remote) =~ s{origin/}{};
    unless ($local eq "master") {
      #if ($opts{move}) {
        $self->git("branch", "--no-track", $local, "refs/remotes/$remote");
        $self->git("branch", "-r", "-D", $remote) 
      #} else {
      #  $self->git("branch", "-t", $local, "refs/remotes/$remote");
      #}
    }
  }
}

sub graft_pre_and_post {
  my $self = shift;
  
  $self->header("Grafting the two halves together...");
  
  $self->cmd("cp", $self->{grafts_file}, ".git/info/grafts");
  $self->git("checkout", "master");
  $self->git("filter-branch", "--tag-name-filter", "cat", "--", "--all");
  # Remove this or else it causes problems later
  unlink ".git/info/grafts";
  
  #$self->chdir("..");
  $self->cmd("rm", "-rf", $self->{git_repo});
  #$self->git("clone", "file://".$pre_repo_path, $self->{git_repo});
  $self->cmd("cp", "-R", $pre_repo_path, $self->{git_repo});
  $self->chdir($self->{git_repo});
  $self->cmd("rm", "-rf", ".git/refs/original");
  $self->cmd("rm", "-rf", ".git/logs");
}

sub relocate_master {
  my $self = shift;
  
  # Remember when we saved post's master branch?
  # Here's where we save it as the new master.
  
  $self->header("Relocating master...");
  
  $self->git("checkout", "post-master");
  $self->git("branch", "-D", "master");
  $self->git("checkout", "-b", "master");
  $self->git("branch", "-D", "post-master");
}

#---

sub graft_message {
  my $self = shift;
  <<EOT;
  
----
Wait, you're not done yet!

At this point, what we've done is split up the SVN repo into two git
repos. Now you just need to graft them together.

Next steps:

1. The last step we did above was actually consolidate the two
   half-repos into one repo, which is stored (for right now) at
   /tmp/git.pre. You'll want to take a look at that in something like
   GitX to find two commit ids, one where the first half ends, the
   other where the second half starts.
   
2. Once you have those commit ids, put them into a grafts file. You
   can read more about grafting here[1], but here's all it needs to
   contain:

     <start of post-repo id> <end of pre-repo id>
   
   So, if the first commit id was AAAAA and the second was BBBBB,
   you'd write:

     AAAAB BBBBB

   You can test the grafts file you just made by creating
   .git/info/grafts in /tmp/git.pre. If you're in GitX, just press
   Command-R to refresh the view.
  
3. Finally, tell this script you're ready to start grafting by
   supplying the --grafts-file option.

[1]: http://git.wiki.kernel.org/index.php/GraftPoint

EOT
}

sub final_message {
  my $self = shift;
  my $git_folder = my $project_name = basename($self->{git_repo});
  $git_folder .= ".git" unless $git_folder =~ m{\.git$};
  <<EOT
  
----
Hey, looks like you made it! You can take a look at your brand-spanking
new git repo at:

  $self->{git_repo}

But you want to get it on your server so other people can use it, right?
So, ssh into your server and try running:

  adduser git
  # ....
  su git
  cd /path/to/git/repos
  mkdir $git_folder
  cd $git_folder
  git init --bare
  git config core.sharedrepository 1
  chmod -R o-rwx .
  chmod -R g=u .
  find . -type d | xargs chmod g+s

Next, log out, navigate to your local repo and tell Git about the
remote repo:

  git remote add origin ssh://you\@yourserver.com/path/to/git/repos/$git_folder

When you're ready, upload it to your server:

  git push origin --all
  
Now for the moment of truth! Let's see if you can clone it:

  git clone ssh://you\@yourserver.com/path/to/git/repos/$git_folder
  
If everything looks good, congratulations! Go and play some Wii, or something.
  
EOT
}
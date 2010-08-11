#!/usr/bin/env perl

package SvnToGit::Converter::ConsistentLayout;

# Need to re-use all these modules?
use Modern::Perl;
use File::Basename;
use Data::Dumper::Again;
use Data::Dumper::Simple;
my $dd = Data::Dumper::Again->new(deepcopy => 1, quotekeys => 1);
my $tdd = Data::Dumper::Again->new(deepcopy => 1, quotekeys => 1, terse => 1, indent => 0);

use parent 'SvnToGit::Converter';

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
  
  $data{clone} = 1 unless exists $data{clone};
  
  for (qw(trunk branches tags)) {
    if ($data{$_}) {
      $data{$_} =~ s{/$}{};
    }
  }
  
  if ($data{strip_tag_prefix}) {
    $data{strip_tag_prefix} =~ s{/$}{};
  }
  
  return %data;
}

=head2 $converter-E<gt>run

Converting a normal repo (either no structure or some structure) is
pretty easy. Here's basically how it works:

=over 4

=item *

Use git-svn to clone the SVN repo (unless C<clone> was set to false)

=item *

Go through branches in the new git repo, creating proper tags from
branches that look like tags and checking out every other branch as
a local branch

=item *

Map trunk to master

=item *

Perform optimizations on the final repo to reduce file size

=back

If converting a repo with an inconsistent structure, the process is a
bit more involved:

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

  if ($self->{clone}) {
    $self->clone();
  } else {
    $self->info("Since you requested not to clone, I'm assuming that you're already in the git repo.");
  }
  
  $self->fix_branches_and_tags();
  $self->optimize_repo();
  chdir ".." if $self->{clone};
}

sub clone {
  my $self = shift;
  
  $self->ensure_git_svn_present();
  
  if ($self->{force}) {
    $self->cmd("rm", "-rf", $self->{git_repo});
  }
  
  mkdir $self->{git_repo};
  $self->chdir($self->{git_repo});

  $self->info("Cloning SVN repo via git-svn...");

  my @clone_opts;
  if ($self->{root_only}) {
    push @clone_opts, "--trunk=".$self->{svn_repo};
  } else {
    for my $opt (qw(trunk branches tags)) {
      push @clone_opts, "--$opt=$self->{$opt}" if $self->{$opt};
    }
    push @clone_opts, "--stdlayout" unless @clone_opts;
  }
  $self->git_svn("init", "--no-metadata", @clone_opts, $self->{svn_repo});
  
  $self->git("config", "svn.authorsfile", $self->{authors_file}) if $self->{authors_file};
  
  my @fetch_opts;
  if ($self->{revisions}) {
    push @fetch_opts, "-r", join(":", @{$self->{revisions}});
  }
  $self->git_svn("fetch", @fetch_opts);
}

sub cache_branches_and_tags {
  my $self = shift;
  my $info = $self->get_branches_and_tags();
  $self->{$_} = $info->{$_} for %$info;
}

sub fix_branches_and_tags {
  my $self = shift;
  $self->cache_branches_and_tags();
  $self->fix_branches();
  $self->fix_tags();
  $self->fix_trunk();
}

sub fix_branches {
  my $self = shift;
  
  $self->info("Checking out remote branches as local branches...");

  for my $branch (@{$self->{remote_branches}}) {
    next if $branch eq $self->trunk_path;
    $self->git("branch", "-t", $branch, "refs/remotes/$branch");
    $self->git("checkout", $branch);
  }
}

sub fix_tags {
  my $self = shift;
  
  $self->info("Turning svn tags cloned as branches into real git tags...");

  my $tags_path = $self->tags_path;
  for my $tag_branch (@{$self->{remote_tags}}) {
    (my $tag = $tag_branch) =~ s{^$tags_path/}{};
    my $newtag = $tag;

    if (my $prefix = $self->{strip_tag_prefix}) {
      $newtag =~ s{^$prefix/}{};
    }
    
    my $subject = $self->strip(`git log -l --pretty=format:'\%s' "$tag_branch"`);
    my $date = $self->strip(`git log -l --pretty=format:'\%ci' "$tag_branch"`);
    #$self->git("checkout", $tag_branch);
    $self->git("tag", "-a", "-m", $subject, $newtag, $tag_branch, {env => {GIT_COMMITTER_DATE => $date}});
    $self->git("branch", "-d", "-r", $tag_branch);
  }
}

sub fix_trunk {
  my $self = shift;
  
  return unless grep { $_ eq $self->trunk_path } @{$self->{remote_branches}};

  $self->info("Making sure master is trunk...");

  $self->git("checkout", $self->trunk_path);
  $self->git("branch", "-D", "master");
  $self->git("checkout", "-f", "-b", "master");
  $self->git("branch", "-d", "-r", $self->trunk_path);
  $self->{remote_branches} = [grep { $_ ne "trunk" } @{$self->{remote_branches}}];
}
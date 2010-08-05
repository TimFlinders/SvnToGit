#!/usr/bin/env perl
#
# A reimplementation of James Coglan's svn2git Ruby script as a Perl
# module and accompanying executable, forked from
# http://github.com/schwern/svn2git by Elliot Winkler.
#
# Changes are as follows:
#
# * Update fix_tags and fix_trunk so they're closer to Ruby script
# * Change default behavior so that the directory for the git repo will
#   be auto-created for you. --no-clone assumes you're already in the
#   git repo, as usual.
# * Allow user to customize new git repo location
# * Make it object-oriented so we can use it in another script
# * Add --root-is-trunk option
# * Rename --noclone to --no-clone
# * Split off command-line stuff to the command-line script
# * Add --revision option that will be passed to git svn fetch
# * Add default authors file
# * Add {"authors_file" => "..."} as an alias for {"authors" => "..."}
#

package SvnToGit;

# don't know if this should be above package or below
use strict;
use warnings;

use File::Basename;

our $DEFAULT_AUTHORS_FILE = "$ENV{HOME}/.svn2git/authors";

#---

sub convert {
  my($class, %args) = @_;
  my $c = $class->new(%args);
  $c->run;
  return $c;
}

sub new {
  my($class, %args) = @_;
  unless ($args{git_repo}) {
    $args{git_repo} = basename($args{svn_repo});
    if (-e $args{git_repo}) {
      $args{git_repo} .= ".git";
    }
  }
  $args{revision} = $args{revisions} if $args{revisions};
  $args{authors} = $args{authors_file} if $args{authors_file};
  $args{clone} = 1 unless exists $args{clone};
  if (-f $DEFAULT_AUTHORS_FILE && !$args{authors}) {
    $args{authors} = $DEFAULT_AUTHORS_FILE;
  }
  if ($args{authors} && ! -f $args{authors}) {
    die "The authors file you specified doesn't exist.\n"
  }
  $args{quiet_option} = $args{quiet} ? "--quiet" : "";
  my $self = \%args;
  bless($self, $class);
  return $self;
}

sub run {
  my $self = shift;
  
  $self->ensure_git_present();

  if ($self->{clone}) {
    $self->clone($self->{svn_repo}, $self->{git_repo});
  } else {
    print "Since you requested not to clone, I'm assuming that you're already in the git repo.\n";
  }
  
  $self->cache_branches();
  $self->fix_tags();
  $self->fix_branches();
  $self->fix_trunk();
  $self->optimize_repo();
  chdir ".." if $self->{clone};
  
  #print "\n----------\n";
  #print "Conversion done!";
  #print " Check out $self->{git_repo}." if $self->{clone};
  #print "\n";
}

sub clone {
  my $self = shift;
  
  $self->ensure_git_svn_present();
  
  if ($self->{force}) {
    $self->run_command(qw(rm -rf), $self->{git_repo});
  }
  if (-e $self->{git_repo}) {
    die "Can't clone to '$self->{git_repo}', that directory is already present!\n";
  }
  mkdir $self->{git_repo};
  chdir $self->{git_repo};

  print "Cloning SVN repo at $self->{svn_repo} into $self->{git_repo}...\n";

  my @clone_opts;
  if ($self->{root_is_trunk}) {
    push @clone_opts, "--trunk=".$self->{svn_repo};
  } else {
    for my $opt (qw(trunk branches tags)) {
      push @clone_opts, "--$opt=$self->{$opt}" if $self->{$opt};
    }
    push @clone_opts, "-s" unless @clone_opts;
  }
  $self->run_command(qw(git svn init $self->{quiet_option} --no-metadata), @clone_opts, $self->{svn_repo});
  
  $self->run_command(qw(git config svn.authorsfile), $self->{authors}) if $self->{authors};
  
  my @fetch_opts;
  push @fetch_opts, "-r", $self->{revision} if $self->{revision};
  $self->run_command(qw(git svn fetch $self->{quiet_option}), @fetch_opts);
}

sub cache_branches {
  my $self = shift;
  $self->{remote_branches} = [map { strip($_) } `git branch -r`];
}

sub fix_tags {
  my $self = shift;
  
  print "Turning svn tags cloned as branches into real git tags...\n";
  
  my $tags_path = $self->{tags} || 'tags/';
  $tags_path .= '/' unless $tags_path =~ m{/$};
  my @tag_branches = grep m{^\Q$tags_path\E}, @{$self->{remote_branches}};

  for my $tag_branch (@tag_branches) {
    qx/git show-ref $tag_branch/;
    if ($?) {
      warn "'$tag_branch' is not a valid branch reference, so skipping..";
      next;
    }

    my($tag) = $tag_branch =~ m{^\Q$tags_path\E(.*)};
    warn "Couldn't find tag name from $tag_branch" unless length $tag;

    if (my $strip = $self->{strip_tag_prefix}) {
      $tag =~ s{^$strip}{};
    }
    
    my $subject = strip(`git log -l --pretty=format:'\%s' "$tag_branch"`);
    my $date = strip(`git log -l --pretty=format:'\%ci' "$tag_branch"`);
    $self->run_command(qw(git checkout $self->{quiet_option}), $tag_branch);
    $self->run_command("GIT_COMMITTER_DATE='$date'", qw(git tag $self->{quiet_option} -a -m), $subject, $tag, $tag_branch);
    $self->run_command(qw(git branch $self->{quiet_option} -d -r), $tag_branch);
  }
}

sub fix_branches {
  my $self = shift;
  
  print "Checking out remote branches as local branches...\n";
  
  my $tags_path = $self->{tags} || 'tags/';
  $tags_path .= '/' unless $tags_path =~ m{/$};
  my @remote_branches = grep !m{^\Q$tags_path}, @{$self->{remote_branches}};

  my $trunk = $self->{trunk} || "trunk";
  for my $branch (@remote_branches) {
    next if $branch eq $trunk;
    
    $self->run_command(qw(git checkout $self->{quiet_option}), $branch);
    $self->run_command(qw(git checkout $self->{quiet_option} -b), $branch);
  }
}

sub fix_trunk {
  my $self = shift;
  
  my $trunk = $self->{trunk} || "trunk";

  return unless grep /^\s*\Q$trunk\E\s*/, @{$self->{remote_branches}};

  print "Making sure master is trunk...\n";

  $self->run_command(qw(git checkout $self->{quiet_option}), $trunk);
  $self->run_command(qw(git branch $self->{quiet_option} -D master));
  $self->run_command(qw(git checkout $self->{quiet_option} -f -b master));
  $self->run_command(qw(git branch $self->{quiet_option} -d -r), $trunk);
}

sub optimize_repo {
  my $self = shift;
  $self->run_command(qw(git gc $self->{quiet_option}));
}

#---

sub ensure_git_present {
  my $self = shift;
  `git --version`;
  die "git --version didn't work.  Is git installed?\n" if $?;
}

sub ensure_git_svn_present {
  my $self = shift;
  `git help svn`;
  die "git help svn didn't work.  Is git-svn installed?\n" if $?;
}

sub run_command {
  my $self = shift;
  
  print "COMMAND: @_\n" if $self->{verbose};
  system @_;

  my $exit = $? >> 8;
  die "@_ exited with $exit" if $exit;

  return 1;
}

# don't need to get self here, since this is kind of a private method
sub strip {
  local $_ = shift;
  s/^\s+//; s/\s+$//;
  return $_;
}

1;
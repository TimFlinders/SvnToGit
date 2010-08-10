#!/bin/bash

set -e

this_script=$(readlink -f $0)
this_dir=`dirname $this_script`
fixtures_dir=$this_dir/fixtures
fixture_dir=$fixtures_dir/root_only_layout
mock_remote_repo=$fixture_dir/repo
mock_local_repo=$fixture_dir/wc

rm -rf $fixture_dir
mkdir -p $fixture_dir

svnadmin create --pre-1.4-compatible $mock_remote_repo
svn co file://$mock_remote_repo $mock_local_repo
cd $mock_local_repo

echo "Lorem ipsum dolor sit amet" > test.txt
svn add test.txt
svn commit -m "Initial commit" --username john
svn up

echo "Add another line from trunk, rev 2" >> test.txt
svn commit -m "Update test.txt from trunk" --username john
svn up

echo "Add another line from trunk, rev 3" >> test.txt
svn commit -m "Update test.txt from trunk, again" --username joe
svn up

echo "Add another line from trunk, rev 4" >> test.txt
svn commit -m "Update test.txt from trunk, yet again" --username jane
svn up

echo "Add another line from trunk, rev 5" >> test.txt
svn commit -m "Update test.txt from trunk for the fourth time" --username jane
svn up

echo "john = John Smith <john@smith.com>" >> $fixture_dir/authors.txt
echo "jane = Jane Doe <jane@doe.com>" >> $fixture_dir/authors.txt
echo "joe = Joe Schmoe <joe@schmoe.com>" >> $fixture_dir/authors.txt
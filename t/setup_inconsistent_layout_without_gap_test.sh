#!/bin/bash

set -e

this_script=$(readlink -f $0)
this_dir=`dirname $this_script`
fixtures_dir=$this_dir/fixtures
fixture_dir=$fixtures_dir/inconsistent_layout_without_gap
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

echo "Here's another line we added in rev 2" >> test.txt
svn commit -m "Update test.txt" --username john
svn up

echo "And another line we added in rev 3" >> test.txt
svn commit -m "Update test.txt, again" --username john
svn up

svn mkdir trunk branches tags
svn commit -m "Add trunk, branches, tags" --username jane
svn up

svn mv test.txt trunk
svn commit -m "Move everything to trunk" --username jane
svn up

echo "Add another line from trunk, rev 6" >> trunk/test.txt
svn commit -m "Update test.txt from trunk" --username jane
svn up

svn copy trunk branches/foo
svn commit -m "Make 'foo' branch" --username joe
svn up

echo "Add another line from foo, rev 8" >> branches/foo/test.txt
svn commit -m "Update test.txt from foo" --username joe
svn up

echo "Add another line from trunk, rev 9" >> trunk/test.txt
svn commit -m "Update test.txt finally, from trunk" --username john
svn up
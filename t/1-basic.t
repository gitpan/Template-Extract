#!/usr/bin/perl
# $File: //member/autrijus/Template-Extract/t/1-basic.t $ $Author: autrijus $
# $Revision: #10 $ $Change: 8521 $ $DateTime: 2003/10/21 22:52:33 $ vim: expandtab shiftwidth=4

use strict;
use Test::More tests => 12;

use_ok('Template::Extract');

my ($template, $document, $data);

my $obj = Template::Extract->new;
isa_ok($obj, 'Template');
isa_ok($obj, 'Template::Extract');

$template = << '.';
<ul>[% FOREACH record %]
<li><A HREF="[% url %]">[% title %]</A>: [% rating %] - [% comment %].
[% ... %]
[% END %]</ul>
.

$document = << '.';
<html><head><title>Great links</title></head><body>
<ul><li><A HREF="http://slashdot.org">News for nerds.</A>: A+ - nice.
this text is ignored.</li>
<li><A HREF="http://microsoft.com">Where do you want...</A>: Z! - yeah.
this text is ignored, too.</li></ul>
.

$data = Template::Extract->new->extract($template, $document);

is_deeply($data, {
    'record' => [ { 
        'rating'    => 'A+',
        'comment'   => 'nice',
        'url'       => 'http://slashdot.org',
        'title'     => 'News for nerds.',
    }, {
        'rating'    => 'Z!',
        'comment'   => 'yeah',
        'url'       => 'http://microsoft.com',
        'title'     => 'Where do you want...',
    } ]
}, 'extract() as documented in synopsis');

$template = << '.';
[% FOREACH subject %]
[% ... %]
<h1>[% sub.heading %]</h1>
<ul>[% FOREACH record %]
<li><A HREF="[% url %]">[% title %]</A>: [% rating %] - [% comment %].
[% ... %]
[% END %]</ul>
[% ... %]
[% END %]
<ol>[% FOREACH record %]
<li><A HREF="[% url %]">[% title %]</A>: [% rating %] - [% comment %].
[% ... %]
[% END %]</ol>
.

$document = << '.';
<html><head><title>Great links</title></head><body>
<h1>Foo</h1>
<ul><li><A HREF="http://slashdot.org">News for nerds.</A>: A+ - nice.
this text is ignored.</li>
<li><A HREF="http://microsoft.com">Where do you want...</A>: Z! - yeah.
this text is ignored, too.</li></ul>
<h1>Bar</h1>
<ul><li><A HREF="http://slashdot.org">News for nerds.</A>: A+ - nice.
this text is ignored.</li>
<li><A HREF="http://microsoft.com">Where do you want...</A>: Z! - yeah.
this text is ignored, too.</li></ul>
<ol><li><A HREF="http://cpan.org">CPAN.</A>: +++++ - cool.
this text is ignored, also.</li></ol>
.

$data = Template::Extract->new->extract($template, $document);

is_deeply($data, {
    'record' => [ { 
        'rating'    => '+++++',
        'comment'   => 'cool',
        'url'       => 'http://cpan.org',
        'title'     => 'CPAN.',
    } ],
    'subject' => [map { {
        'sub' => { 'heading' => $_ },
        'record' => [ { 
            'rating'    => 'A+',
            'comment'   => 'nice',
            'url'       => 'http://slashdot.org',
            'title'     => 'News for nerds.',
        }, {
            'rating'    => 'Z!',
            'comment'   => 'yeah',
            'url'       => 'http://microsoft.com',
            'title'     => 'Where do you want...',
        } ]
    } } qw(Foo Bar)],
}, 'extract() with two nested and one extra FOREACH');

$template = << '.';
_[% C %][% D %]_
_[% D %][% E %]_
_[% E %][% D %][% C %]_
.

$document = << '.';
_doeray_
_rayme_
_meraydoe_
.

$data = Template::Extract->new->extract($template, $document);

is_deeply($data, {
    'C' => 'doe',
    'D' => 'ray',
    'E' => 'me',
}, 'extract() with backtracking');

my $ext_data = { F => 'fa' };
$data = Template::Extract->new->extract($template, $document, $ext_data);

is_deeply($data, {
    'C' => 'doe',
    'D' => 'ray',
    'E' => 'me',
    'F' => 'fa',
}, 'extract() with external data');

is_deeply($data, $ext_data, 'extract() should return the same data');

$template = << '.';
[% FOREACH entry %]
[% ... %]
<div>[% FOREACH title %]<i>[% title_text %]</i>[% END %]<br>[% content %]</div>
  ([% FOREACH comment %][% SET sub.comment = 1 %]<b>[% comment_text %]</b> |[% END %]Comment on this)
[% END %]
.

$document = << '.';
<div><i>Title 1</i><i>Title 1.a</i><br>xxx</div>
  (<b>1 Comment</b> |Comment on this)
<div><i>Title 2</i><br>foo</div>
  (Comment on this)
.

$data = Template::Extract->new->extract( $template, $document );

is_deeply($data, {
    'entry' => [ { 
        'comment'   => [ {
            'comment_text' => '1 Comment',
            'sub' => { 'comment' => 1 },
        } ],
        'content'   => 'xxx',
        'title'   => [ {
            'title_text' => 'Title 1',
        }, {
            'title_text' => 'Title 1.a',
        } ],
    }, {
        'content'   => 'foo',
        'title'   => [ {
            'title_text' => 'Title 2',
        } ],
    } ],
}, 'extract() with two FOREACHs nested inside a FOREACH');

$template = << '.';
[% FOREACH top %][% FOREACH foo %][% SET bar.x = "set" %]<[% baz.y %]|[% qux.z %]>[% END %][% END %]
.

$document = << '.';
<test1|1><test2|2><test3
.

$data = Template::Extract->new->extract($template, $document);

is_deeply($data, { top => [{ foo => [{
    bar => { x => 'set' },
    baz => { y => 'test1' },
    qux => { z => '1' },
}, {
    bar => { x => 'set' },
    baz => { y => 'test2' },
    qux => { z => '2' },
}] }] }, 'extract() with SET directive inside two FOREACHs');

$template = "[% FOREACH item %]hello [% foo %]<br>[% END %]";
$document = " hello name<br>";

$data = Template::Extract->new->extract($template, $document);

is_deeply($data, { item => [ { foo => 'name' } ] }, 'extract() with extra prepended data');

$Template::Extract::EXACT =
$Template::Extract::EXACT = 1;
$data = Template::Extract->new->extract($template, $document);

is($data, undef, 'extract() fails with a partial match when $EXACT == 1');


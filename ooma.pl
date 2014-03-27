#!/usr/bin/perl -w
#
#
# ooma.pl - Give me my mp3 voicemail in an email without paying for Ooma Premier
#
# @gitrc - summer 2010
#
# screen scraping still valuable

use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Cookies;
use File::Slurp;
use MIME::Lite;
use Data::Dumper;
use strict;

my $debug;
$debug = exists( $ENV{SSH_CLIENT} ) ? 1 : 0;

my $auth_url  = 'https://my.ooma.com/home/login';
my $inbox_url = 'https://my.ooma.com/inbox';
my $log_url   = 'https://my.ooma.com/call_logs/export';

my $username     = 'username';
my $password     = 'password';
my $submit_value = 'commit';

my $ua = LWP::UserAgent->new;
$ua->agent("Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1)");

$ua->cookie_jar(
    HTTP::Cookies->new(
        file           => "ooma_cookies",
        autosave       => 0,
        ignore_discard => 0
    )
);

my $content = $ua->get($auth_url)->as_string;
die "Couldn't get $auth_url" unless defined $content;

$content =~ m/"authenticity_token"[^<]+value="(.*?)"/;
my $token = $1;

$content = $ua->request(
    POST $auth_url ,
    [
        username           => $username,
        password           => $password,
        authenticity_token => $token
    ]
);
die "Couldn't get $auth_url" unless defined $content;

$content = $ua->get($inbox_url)->as_string;
die "Couldn't get $inbox_url" unless defined $content;
$content =~
  m/download_message\?caller_name=(\d+)\&amp;message_uid=(\w+-\w+-\w+-\w+-\w+)/;
my $caller    = $1;
my $uidnumber = $2;

my $file_url =
"https://my.ooma.com/inbox/download_message?caller_name=$caller&message_uid=$uidnumber";
print "DEBUG: caller=$caller uidnumber=$uidnumber file_url = $file_url\n"
  if $debug;

$content = $ua->get($file_url)->as_string;
write_file( '/tmp/message.mp3', { binmode => ':raw' }, $content );

my $response = $ua->get($log_url);
$content = $response->content;

my @content = split( "\n", $content );

my @missed = grep( /Missed/, @content );

my $line = $missed[0];
print "DEBUG LOGLINE: $line\n" if $debug;

my $callerid;
my ( $type, $local, $remote, $id, $date, $duration ) = split( /\t/, $line );
if ( $id eq " " ) {
    $callerid = $remote;
}
else {
    $callerid = $id;
}

my $filename = "/tmp/message.mp3";

# Cleanup the body
my $body = "Date/Time                   Caller
$date   $remote";
my $subject = "New VM from $callerid";

# Generate the Email

### Create a new multipart message:
my $msg = MIME::Lite->new(
    From    => 'vm-notify@ooma.com',
    To      => 'you@example.com',
    Cc      => 'your_wife@example.com',
    Subject => $subject,
    Type    => 'multipart/mixed'
);

#$msg->add('X-Priority' => 1);

### Add parts (each "attach" has same arguments as "new"):
$msg->attach(
    Type => 'TEXT',
    Data => $body
);
$msg->attach(
    Type        => 'audio/mpeg',
    Path        => $filename,
    Disposition => 'attachment'
);

# send the email
if ($debug) {
    print Dumper $msg;
}
else {
    MIME::Lite->send( 'smtp', 'localhost', Timeout => 10 );
    $msg->send();
}

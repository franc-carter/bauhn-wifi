#!/usr/bin/perl -w
#
# Based on 
#  http://forums.ninjablocks.com/index.php?
#   p=/discussion/2931/aldi-remote-controlled-power-points-5-july-2014/p1
#  and 
#   http://pastebin.ca/2818088

use strict;
use IO::Socket;
use IO::Select;
use IO::Interface::Simple;
use Data::Dumper;

my $port = 10000;

my $fbk_preamble = pack('C*', (0x68,0x64,0x00,0x1e,0x63,0x6c));
my $ctl_preamble = pack('C*', (0x68,0x64,0x00,0x17,0x64,0x63));
my $ctl_on       = pack('C*', (0x00,0x00,0x00,0x00,0x01));
my $ctl_off      = pack('C*', (0x00,0x00,0x00,0x00,0x00));
my $twenties     = pack('C*', (0x20,0x20,0x20,0x20,0x20,0x20));
my $onoff        = pack('C*', (0x68,0x64,0x00,0x17,0x73,0x66));
my $subscribed   = pack('C*', (0x68,0x64,0x00,0x18,0x63,0x6c));

sub findBauhnOnInterface($$)
{
    my ($mac,$if) = @_;

    my $bauhn;
    my $reversed_mac = scalar(reverse($mac));
    my $subscribe    = $fbk_preamble.$mac.$twenties.$reversed_mac.$twenties;

    my $socket = IO::Socket::INET->new(Proto=>'udp', LocalPort=>$port, Broadcast=>1) ||
                     die "Could not create listen socket: $!\n";
    my $select = IO::Select->new($socket) ||
                     die "Could not create Select: $!\n";

    my $to_addr = sockaddr_in($port, inet_aton($if->broadcast));
    $socket->send($subscribe, 0, $to_addr) ||
        die "Send error: $!\n";

    my $n = 0;
    while($n < 2) {
        my @ready = $select->can_read(0.5);
        foreach my $fh (@ready) {
            my $packet;
            my $from = $socket->recv($packet,1024) || die "recv: $!";
            if ((substr($packet,0,6) eq $subscribed) && (substr($packet,6,6) eq $mac)) {
                my ($port, $iaddr) = sockaddr_in($from);
                $bauhn->{mac}      = $mac;
                $bauhn->{saddr}    = $from;
                $bauhn->{socket}   = $socket;
                $bauhn->{on}       = (substr($packet,-1,1) eq chr(1));
                return $bauhn;
            }
        }
        $n++;
    }
    close($socket);
    return undef;
}

sub findBauhn($)
{
    my ($mac) = @_;


    my @interfaces = IO::Interface::Simple->interfaces;
    @interfaces = grep(!/^lo$/, @interfaces);
    
    for my $if (@interfaces) {
        my $bauhn = findBauhnOnInterface($mac, $if);
        if (defined($bauhn)) {
            return $bauhn;
        }
    }
    return undef;
}


sub controlBauhn($$)
{
    my ($bauhn,$action) = @_;

 
   my $mac = $bauhn->{mac};

    if ($action eq "on") {
        $action   = $ctl_preamble.$mac.$twenties.$ctl_on;
    }
    if ($action eq "off") {
        $action   = $ctl_preamble.$mac.$twenties.$ctl_off;
    }

    my $select = IO::Select->new($bauhn->{socket}) ||
                     die "Could not create Select: $!\n";

    my $n = 0;
    while($n < 2) {
        $bauhn->{socket}->send($action, 0, $bauhn->{saddr}) ||
            die "Send error: $!\n";

        my @ready = $select->can_read(0.5);
        foreach my $fh (@ready) {
            my $packet;
            my $from = $bauhn->{socket}->recv($packet,1024) ||
                           die "recv: $!";
            my @data = unpack("C*", $packet);
            my @packet_mac = @data[6..11];
            if (($onoff eq substr($packet,0,6)) && ($mac eq substr($packet,6,6))) {
                return 1;
            }
        }
        $n++;
    }
    return 0;
}

($#ARGV == 1) || die "Usage: $0 XX:XX:XX:XX:XX:XX <on|off|status>\n";

my @mac = split(':', $ARGV[0]);
($#mac == 5) || die "Usage: $0 XX:XX:XX:XX:XX:XX <on|off|status>\n";

@mac = map { hex("0x".$_) } split(':', $ARGV[0]);
my $mac = pack('C*', @mac);

my $bauhn = findBauhn($mac);
defined($bauhn) || die "Could not find Bauhn with mac of $ARGV[0]\n";
controlBauhn($bauhn, $ARGV[1]) || "Could not turn Bauhn $ARGV[1]\n";




package Win32::IPConfig::Adapter;

use 5.006;
use strict;
use warnings;

use Win32::TieRegistry qw/:KEY_/;

sub new
{
    my $class = shift;

    my $hklm = shift; # connection to registry
    my $nic = shift;

    my $osversion = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\CurrentVersion"};

    my $networkcards = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\NetworkCards"};
    my $description = $networkcards->{$nic}{"Description"};
    my $id = $networkcards->{$nic}{"ServiceName"};

    my $services = $hklm->{"SYSTEM\\CurrentControlSet\\Services"};

    my $self = {};
    $self->{"osversion"} = $osversion;
    $self->{"id"} = $id;
    $self->{"description"} = $description;

    # connect to the appropriate registry keys
    my $tcpipparams = $services->{"Tcpip\\Parameters"};
    my $adapterparams;
    my $tcpipadapterparams;
    if ($osversion eq "5.0") {
        $tcpipadapterparams = $services->{"Tcpip\\Parameters\\Interfaces\\$id"};
        $adapterparams = $services->{"$id\\Parameters\\Tcpip"};
    } elsif ($osversion eq "4.0") {
        $adapterparams = $services->{"$id\\Parameters\\Tcpip"};
    }

    # dhcp enabled?
    if ($osversion eq "5.0") {
        # available both from $adapterparams and $tcpipadapterparams
        $self->{"dhcp_enabled"} = hex($tcpipadapterparams->{"EnableDHCP"});
    } elsif ($osversion eq "4.0") {
        # available only from $adapterparams
        $self->{"dhcp_enabled"} = hex($adapterparams->{"EnableDHCP"});
    }

    # ip addresses
    if ($osversion eq "5.0") {
        # available both from $adapterparams and $tcpipadapterparams
        if ($self->{"dhcp_enabled"}) {
            my $dhcpipaddress = $tcpipadapterparams->{"DHCPIPAddress"};
            $self->{ipaddresses} = [$dhcpipaddress];
        } else {
            my @ipaddresses = @{$tcpipadapterparams->{"IPAddress"}};
            if ($ipaddresses[0] eq "0.0.0.0") {
                die "invalid static ip address";
                # perhaps it autoconfigured?
            }
            $self->{ipaddresses} = \@ipaddresses;
        }
    } elsif ($osversion eq "4.0") {
        # available only from $adapterparams
        if ($self->{"dhcp_enabled"}) {
            my $dhcpipaddress = $adapterparams->{"DHCPIPAddress"};
            $self->{ipaddresses} = [$dhcpipaddress];
        } else {
            my @ipaddresses = @{$adapterparams->{"IPAddress"}};
            if ($ipaddresses[0] eq "0.0.0.0") {
                die "invalid static ip address";
                # perhaps it autoconfigured?
            }
            $self->{ipaddresses} = \@ipaddresses;
        }
    }

    # connection-specific domain (for Windows 2000+)
    if ($osversion eq "5.0") {
        # available only from $tcpipadapterparams
        $self->{"domain"} = $tcpipadapterparams->{"Domain"} || "";
    } elsif ($osversion eq "4.0") {
        $self->{"domain"} = "";
    }

    # dns servers
    my @nameservers = ();
    if ($osversion eq "5.0") {
        # available only from $tcpipadapterparams
        if ($self->{"dhcp_enabled"}) {
            @nameservers = split / /, $tcpipadapterparams->{"DhcpNameServer"};
        } else {
            @nameservers = split /,/, $tcpipadapterparams->{"NameServer"};
        }
    } elsif ($osversion eq "4.0") {
        # actually a NT4 host setting rather than an adapter one
        if ($self->{"dhcp_enabled"}) {
            @nameservers = split / /, $tcpipparams->{"DhcpNameServer"};
        } else {
            @nameservers = split / /, $tcpipparams->{"NameServer"};
        }
    }
    @nameservers = grep { $_ } @nameservers; # remove empty entries
    $self->{"dns"} = \@nameservers;

    # wins servers
    my @wins = ();
    if ($osversion eq "5.0") {
        my $netbt = $services->{"Netbt\\Parameters\\Interfaces\\Tcpip_$id"};
        if ($self->{"dhcp_enabled"}) {
            @wins = @{$netbt->{'DhcpNameServerList'}};
        } else {
            @wins = @{$netbt->{'NameServerList'}};
        }
    } elsif ($osversion eq "4.0") {
        my $netbt = $services->{"Netbt\\Adapters\\$id"};
        if ($self->{"dhcp_enabled"}) {
            my $nameserver = $netbt->{"DhcpNameServer"};
            my $nameserverbackup = $netbt->{"DhcpNameServerBackup"};
            push @wins, $nameserver if $nameserver;
            push @wins, $nameserverbackup if $nameserverbackup;
        } else {
            my $nameserver = $netbt->{"NameServer"};
            my $nameserverbackup = $netbt->{"NameServerBackup"};
            push @wins, $nameserver if $nameserver;
            push @wins, $nameserverbackup if $nameserverbackup;
        }
    }
    @wins = grep { $_ } @wins; # remove empty entries
    $self->{"wins"} = \@wins;

    # default gateways
    my @gateways = ();
    if ($osversion eq "5.0") {
        # available both from $adapterparams and $tcpipadapterparams
        if ($self->{"dhcp_enabled"}) {
            @gateways = @{$tcpipadapterparams->{"DhcpDefaultGateway"}};
        } else {
            @gateways = @{$tcpipadapterparams->{"DefaultGateway"}};
        }
    } elsif ($osversion eq "4.0") {
        # available only from $adapterparams
        if ($self->{"dhcp_enabled"}) {
            @gateways = @{$adapterparams->{"DhcpDefaultGateway"}};
        } else {
            @gateways = @{$adapterparams->{"DefaultGateway"}};
        }
    }
    @gateways = grep { $_ } @gateways; # remove empty entries
    $self->{"gateways"} = \@gateways;

    bless $self, $class;
    return $self;
}

sub get_id { return $_[0]->{"id"}; }
sub get_description { return $_[0]->{"description"}; }
sub get_ipaddresses { return $_[0]->{"ipaddresses"}; }
sub is_dhcp_enabled { return $_[0]->{"dhcp_enabled"}; }
sub get_gateways { return $_[0]->{"gateways"}; }
sub get_dns { return $_[0]->{"dns"}; }
sub get_wins { return $_[0]->{"wins"}; }
sub get_domain { return $_[0]->{"domain"}; }

sub dump
{
    my $self = shift;

    print $self->get_id, "\n";
    print $self->get_description, "\n";

    print "dhcp_enabled=", $self->is_dhcp_enabled, "\n";
    
    my @ipaddresses = @{$self->get_ipaddresses};
    print "ipaddresses=@ipaddresses (", scalar @ipaddresses, ")\n";

    my @gateways = @{$self->get_gateways};
    print "gateways=@gateways (", scalar @gateways, ")\n";

    print "domain=", $self->get_domain, "\n";

    my @dns = @{$self->get_dns};
    print "dns=@dns (", scalar @dns, ")\n";

    my @wins = @{$self->get_wins};
    print "wins=@wins (", scalar @wins, ")\n";
}

1;

# What changes will require a reboot?
#
# Windows NT
# Remotely set the domain, and it took effect immediately in an ipconfig.
# Adding a dns server requires a reboot
# Changing a wins server requires a reboot
#
# Windows 2000
# A change to the primary domain on Windows 2000 requires a reboot
# This is not necessary for changing the connection-specific domain.

__END__

=head1 NAME

Win32::IPConfig::Adapter - Windows NT/2000 Network Adapter IP Configuration Settings

=head1 SYNOPSIS

    use Win32::IPConfig;

    $host = shift || "";
    if ($ipconfig = Win32::IPConfig->new($host)) {
        print "hostname=", $ipconfig->get_hostname, "\n";
        print "domain=", $ipconfig->get_domain, "\n";
        print "nodetype=", $ipconfig->get_nodetype, "\n";

        for $adapter (@{$ipconfig->get_adapters}) {
            print "\nAdapter ";
            print $adapter->get_id, "\n";
            print $adapter->get_description, "\n";

            if ($adapter->is_dhcp_enabled) {
                print "DHCP is enabled\n";
            } else {
                print "DHCP is not enabled\n";
            }

            @ipaddresses = @{$adapter->get_ipaddresses};
            print "ipaddresses=@ipaddresses (", scalar @ipaddresses, ")\n";

            @gateways = @{$adapter->get_gateways};
            print "gateways=@gateways (", scalar @gateways, ")\n";

            print "domain=", $adapter->get_domain, "\n";

            @dns = @{$adapter->get_dns};
            print "dns=@dns (", scalar @dns, ")\n";

            @wins = @{$adapter->get_wins};
            print "wins=@wins (", scalar @wins, ")\n";
        }
    }

=head1 DESCRIPTION

Win32::IPConfig::Adapter encapsulates the TCP/IP 
configuration settings for a Windows NT/2000 network adapter.

=head2 METHODS

=over 4

=item $adapter->is_dhcp_enabled

Returns 1 if DHCP is enabled, 0 if it is not. If DHCP is enabled, the values
returned from the get_ipaddresses, get_gateways, get_dns, and get_wins methods
will be retrieved from the dhcp-specific registry keys.

=item $adapter->get_ipaddresses

Returns a reference to a list of ip addresses for this adapter.

=item $adapter->get_gateways

Returns a reference to a list containing default gateway ip addresses. (Bet you
didn't realise Windows NT/2000 allowed you to have multiple default gateways.)
If no default gateways are configured, a reference to an empty list will
be returned.

=item $adapter->get_dns

Returns a reference to a list containing DNS server ip addresses. If no DNS
servers are configured, a reference to an empty list will be returned.

=item $adapter->get_wins

Returns a reference to a list containing WINS server ip addresses. If no WINS
servers are configured, a reference to an empty list will be returned.

=back

=head1 AUTHOR

James Macfarlane, E<lt>jmacfarla@cpan.orgE<gt>

=back

=cut

package Win32::IPConfig::Adapter;

use 5.006;
use strict;
use warnings;

use Carp;
use Win32::TieRegistry qw/:KEY_/;
use POSIX qw/strftime/;

sub new
{
    my $class = shift;

    my $hklm = shift; # connection to registry
    my $nic = shift;

    my $osversion = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\CurrentVersion"};

    my $networkcards = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\NetworkCards"};
    my $description = $networkcards->{$nic}{"Description"};
    my $id = $networkcards->{$nic}{"ServiceName"};

    my $self = {};
    $self->{"nic"} = $nic;
    $self->{"osversion"} = $osversion;
    $self->{"id"} = $id;
    $self->{"description"} = $description;

    # connect to the appropriate registry keys
    my $services = $hklm->{"SYSTEM\\CurrentControlSet\\Services"};
    my $tcpipparams = $services->{"Tcpip\\Parameters"}
        or return undef; # quit if key is missing
    my $adapterparams = $services->{"$id\\Parameters\\Tcpip"}
        or return undef;
    my $tcpipadapterparams;
    my $netbtadapter;
    if ($osversion eq "5.0" || $osversion eq "5.1") {
        $tcpipadapterparams = $services->{"Tcpip\\Parameters\\Interfaces\\$id"}
            or return undef;
        $netbtadapter = $services->{"Netbt\\Parameters\\Interfaces\\Tcpip_$id"};
    } elsif ($osversion eq "4.0") {
        $netbtadapter = $services->{"Netbt\\Adapters\\$id"};
    }
    $self->{"services"} = $services;
    $self->{"tcpipparams"} = $tcpipparams;
    $self->{"adapterparams"} = $adapterparams;
    $self->{"tcpipadapterparams"} = $tcpipadapterparams;
    $self->{"netbtadapter"} = $netbtadapter;

    # dhcp enabled?
    if ($osversion eq "5.0" || $osversion eq "5.1") {
        # available both from "adapterparams" and "tcpipadapterparams"
        $self->{"dhcp_enabled"} = hex($self->{"tcpipadapterparams"}{"EnableDHCP"});
    } elsif ($osversion eq "4.0") {
        # available only from "adapterparams"
        $self->{"dhcp_enabled"} = hex($self->{"adapterparams"}{"EnableDHCP"});
    }

    bless $self, $class;
    return $self;
}

sub get_id { return $_[0]->{"id"}; }

sub get_description { return $_[0]->{"description"}; }

sub is_dhcp_enabled { return $_[0]->{"dhcp_enabled"}; }

sub _get_static_ipaddresses
{
    my $self = shift;

    my @ipaddresses = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available both from "adapterparams" and "tcpipadapterparams"
        if (my $ipaddresses = $self->{"tcpipadapterparams"}{"IPAddress"}) {
            @ipaddresses = @{$ipaddresses};
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        # available only from "adapterparams"
        if (my $ipaddresses = $self->{"adapterparams"}{"IPAddress"}) {
            @ipaddresses = @{$ipaddresses};
        }
    }
    return @ipaddresses;
}

sub _get_dhcp_ipaddresses
{
    my $self = shift;

    my @ipaddresses = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available both from "adapterparams" and "tcpipadapterparams"
        if (my $dhcpipaddress = $self->{"tcpipadapterparams"}{"DHCPIPAddress"}) {
            @ipaddresses = ($dhcpipaddress);
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        # available only from "adapterparams"
        if (my $dhcpipaddress = $self->{"adapterparams"}{"DHCPIPAddress"}) {
            @ipaddresses = ($dhcpipaddress);
        }
    }
    return @ipaddresses;
}

sub get_ipaddresses
{
    my $self = shift;

    # Note: according to Q120642, if IPAddress has a first value
    # set to something other than 0.0.0.0, it will override DHCPIPAddress. 
    # However, in testing, ipconfig did NOT show the statically
    # assigned IP addresses overriding the DHCP IP address.
    # Additionally, pings showed that the original DHCP IP address
    # was still being used.
    
    # Anyway, I still can't get my head around statically configured
    # IP addresses on an adapter that is enabled for DHCP.

    my @ipaddresses = $self->_get_static_ipaddresses;
    if ($self->is_dhcp_enabled) {
        @ipaddresses = $self->_get_dhcp_ipaddresses;
    }
    return wantarray ? @ipaddresses : \@ipaddresses;
}

sub _get_static_subnet_masks
{
    my $self = shift;

    my @subnet_masks = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available both from "adapterparams" and "tcpipadapterparams"
        if (my $subnet_masks = $self->{"tcpipadapterparams"}{"SubnetMask"}) {
            @subnet_masks = @{$subnet_masks};
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        # available only from "adapterparams"
        if (my $subnet_masks = $self->{"adapterparams"}{"SubnetMask"}) {
            @subnet_masks = @{$subnet_masks};
        }
    }
    return @subnet_masks;
}

sub _get_dhcp_subnet_masks
{
    my $self = shift;

    my @subnet_masks = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available both from "adapterparams" and "tcpipadapterparams"
        if (my $subnet_masks = $self->{"tcpipadapterparams"}{"DhcpSubnetMask"}) {
            @subnet_masks = ($subnet_masks);
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        # available only from "adapterparams"
        if (my $subnet_masks = $self->{"adapterparams"}{"DhcpSubnetMask"}) {
            @subnet_masks = ($subnet_masks);
        }
    }
    return @subnet_masks;
}

sub get_subnet_masks
{
    my $self = shift;

    # statically configured subnet masks override dhcp assigned subnet mask
    # but the comments attached to get_ipaddress also apply here
    my @subnet_masks = $self->_get_static_subnet_masks;
    if ($self->is_dhcp_enabled) {
        @subnet_masks = $self->_get_dhcp_subnet_masks;
    }
    return wantarray ? @subnet_masks : \@subnet_masks;
}

sub _get_static_gateways
{
    my $self = shift;

    my @gateways = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available both from "adapterparams" and "tcpipadapterparams"
        if (my $gateways = $self->{"tcpipadapterparams"}{"DefaultGateway"}) {
            @gateways = @{$gateways};
            @gateways = grep { $_ } @gateways; # remove empty entries
        } else {
            @gateways = (); # no statically configured gateways
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        # available only from "adapterparams"
        if (my $gateways = $self->{"adapterparams"}{"DefaultGateway"}) {
            @gateways = @{$gateways};
            @gateways = grep { $_ } @gateways; # remove empty entries
        } else {
            @gateways = (); # no statically configured gateways
        }
    }
    return @gateways;
}

sub _get_dhcp_gateways
{
    my $self = shift;

    my @gateways = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available both from "adapterparams" and "tcpipadapterparams"
        if (my $gateways = $self->{"tcpipadapterparams"}{"DhcpDefaultGateway"}) {
            @gateways = @{$gateways};
        } else {
            @gateways = (); # no dhcp assigned gateways
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        # available only from "adapterparams"
        if (my $gateways = $self->{"adapterparams"}{"DhcpDefaultGateway"}) {
            @gateways = @{$gateways};
        } else {
            @gateways = (); # no dhcp assigned gateways
        }
    }
    return @gateways;
}

sub get_gateways
{
    my $self = shift;
    
    # statically configured gateways override dhcp assigned gateways
    my @gateways = $self->_get_static_gateways;
    if (@gateways == 0 && $self->is_dhcp_enabled) {
        @gateways = $self->_get_dhcp_gateways;
    }
    return wantarray ? @gateways : \@gateways;
}

sub _get_static_dns
{
    my $self = shift;

    my @dns = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available only from "tcpipadapterparams"
        if (my $dns = $self->{"tcpipadapterparams"}{"NameServer"}) {
            @dns = split /,/, $dns;
        } else {
            @dns = (); # no statically configured dns servers
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        # actually a NT4 host setting rather than an adapter one
        if (my $dns = $self->{"tcpipparams"}{"NameServer"}) {
            @dns = split / /, $dns;
        } else {
            @dns = (); # no statically configured dns servers
        }
    }
    return @dns;
}

sub _get_dhcp_dns
{
    my $self = shift;

    my @dns = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available only from "tcpipadapterparams"
        if (my $dns = $self->{"tcpipadapterparams"}{"DhcpNameServer"}) {
            @dns = split / /, $dns;
        } else {
            @dns = (); # no dhcp assigned dns servers
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        # actually a NT4 host setting rather than an adapter one
        if (my $dns = $self->{"tcpipparams"}{"DhcpNameServer"}) {
            @dns = split / /, $dns;
        } else {
            @dns = (); # no dhcp assigned dns servers
        }
    }
    return @dns;
}

sub get_dns
{
    my $self = shift;

    # statically configured dns servers override dhcp assigned dns servers
    my @dns = $self->_get_static_dns;
    if (@dns == 0 && $self->is_dhcp_enabled) {
        @dns = $self->_get_dhcp_dns;
    }
    return wantarray ? @dns : \@dns;
}

sub _get_static_wins
{
    my $self = shift;

    my @wins = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        if (my $wins = $self->{"netbtadapter"}{"NameServerList"}) {
            @wins = @{$wins};
            @wins = grep { $_ } @wins; # remove empty entries
        } else {
            @wins = (); # no statically configured wins servers
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        my $nameserver = $self->{"netbtadapter"}{"NameServer"};
        my $nameserverbackup = $self->{"netbtadapter"}{"NameServerBackup"};
        push @wins, $nameserver if $nameserver;
        push @wins, $nameserverbackup if $nameserverbackup;
    }
    return @wins;
}

sub _get_dhcp_wins
{
    my $self = shift;

    my @wins = ();
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        if (my $wins = $self->{"netbtadapter"}{"DhcpNameServerList"}) {
            @wins = @{$wins};
        } else {
            @wins = (); # no dhcp assigned wins servers
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        my $nameserver = $self->{"netbtadapter"}{"DhcpNameServer"};
        my $nameserverbackup = $self->{"netbtadapter"}{"DhcpNameServerBackup"};
        push @wins, $nameserver if $nameserver;
        push @wins, $nameserverbackup if $nameserverbackup;
    }
    return @wins;
}

sub get_wins
{
    my $self = shift;

    # statically configured wins servers override dhcp assigned wins servers
    my @wins = $self->_get_static_wins;
    if (@wins == 0 && $self->is_dhcp_enabled) {
        @wins = $self->_get_dhcp_wins;
    }
    return wantarray ? @wins : \@wins;
}

sub _get_static_domain
{
    my $self = shift;

    my $domain;
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available only from "tcpipadapterparams"
        $domain = $self->{"tcpipadapterparams"}{"Domain"};
    } elsif ($self->{"osversion"} eq "4.0") {
        # actually an NT4 host-specific setting
        $domain = $self->{"tcpipparams"}{"Domain"};
    }
    return $domain || "";
}

sub _get_dhcp_domain
{
    my $self = shift;

    my $domain;
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available only from "tcpipadapterparams"
        $domain = $self->{"tcpipadapterparams"}{"DhcpDomain"};
    }
    return $domain || "";
}

sub get_domain
{
    my $self = shift;

    # statically configured domain overrides dhcp configured domain
    my $domain = $self->_get_static_domain;
    if ($self->is_dhcp_enabled && $domain eq "") {
        $domain = $self->_get_dhcp_domain;
    }
    return $domain;
}

sub set_domain
{
    my $self = shift;

    my $domain = shift;
    # bail if dhcp enabled
    croak "Adapter is configured through DHCP" if $self->is_dhcp_enabled;

    croak "Invalid Domain Name Suffix" unless $domain =~ /^[\w\.]+$/;

    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        $self->{"tcpipadapterparams"}{"Domain"} = $domain;
    } elsif ($self->{"osversion"} eq "4.0") {
        $self->{"tcpipparams"}{"Domain"} = $domain;
    }
}

sub set_dns
{
    my $self = shift;

    # bail if dhcp enabled
    croak "Adapter is configured through DHCP" if $self->is_dhcp_enabled;

    my @dns = @_;
    for (@dns) {
        croak "Invalid IP address" if $_ !~ /^\d+\.\d+\.\d+\.\d+$/;
    }
    # could also check number of dns servers?

    @dns = grep { $_ } @dns; # remove empty entries
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available only from "tcpipadapterparams"
        $self->{"tcpipadapterparams"}{"NameServer"} = join(",", @dns);
    } elsif ($self->{"osversion"} eq "4.0") {
        # actually a NT4 host setting rather than an adapter one
        $self->{"tcpipparams"}{"NameServer"} = join(" ", @dns);
    }
}

sub set_wins
{
    my $self = shift;

    # bail if dhcp enabled
    croak "Adapter is configured through DHCP" if $self->is_dhcp_enabled;

    my @wins = @_;
    for (@wins) {
        croak "Invalid IP address" if $_ !~ /^\d+\.\d+\.\d+\.\d+$/;
    }
    # could also check number of wins servers?

    @wins = grep { $_ } @wins; # remove empty entries
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        $self->{"netbtadapter"}{"NameServerList"} = [[@wins], "REG_MULTI_SZ"];
    } elsif ($self->{"osversion"} eq "4.0") {
        $self->{"netbtadapter"}{"NameServer"} = $wins[0];
        $self->{"netbtadapter"}{"NameServerBackup"} = $wins[1];
    }
}

sub get_dhcp_server
{
    my $self = shift;

    croak "Adapter is not configured through DHCP"
        unless $self->is_dhcp_enabled;

    my $dhcpserver;
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        # available both from "adapterparams" and "tcpipadapterparams"
        $dhcpserver = $self->{"tcpipadapterparams"}{"DhcpServer"} || "";
    } elsif ($self->{"osversion"} eq "4.0") {
        # available only from "adapterparams"
        $dhcpserver = $self->{"adapterparams"}{"DhcpServer"} || "";
    }
    return $dhcpserver;
}

sub get_dhcp_lease_obtained_time
{
    my $self = shift;

    croak "Adapter is not configured through DHCP"
        unless $self->is_dhcp_enabled;

    my $fmt = "%Y-%m-%d %H:%M";
    my $lease_obtained;
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        if (my $time = $self->{"tcpipadapterparams"}{"LeaseObtainedTime"}) {
            $lease_obtained = strftime($fmt, localtime hex($time));
        } else {
            $lease_obtained = "";
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        if (my $time = $self->{"adapterparams"}{"LeaseObtainedTime"}) {
            $lease_obtained = strftime($fmt, localtime hex($time));
        } else {
            $lease_obtained = "";
        }
    }
    return $lease_obtained;
}

sub get_dhcp_lease_terminates_time
{
    my $self = shift;

    croak "Adapter is not configured through DHCP"
        unless $self->is_dhcp_enabled;

    my $fmt = "%Y-%m-%d %H:%M";
    my $lease_terminates;
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        if (my $time = $self->{"tcpipadapterparams"}{"LeaseTerminatesTime"}) {
            $lease_terminates = strftime($fmt, localtime hex($time));
        } else {
            $lease_terminates = "";
        }
    } elsif ($self->{"osversion"} eq "4.0") {
        if (my $time = $self->{"adapterparams"}{"LeaseTerminatesTime"}) {
            $lease_terminates = strftime($fmt, localtime hex($time));
        } else {
            $lease_terminates = "";
        }
    }
    return $lease_terminates;
}

sub dump
{
    my $self = shift;

    print $self->get_id, "\n";
    print $self->get_description, "\n";

    print "domain=", $self->get_domain, " ";
    if ($self->_get_static_domain && $self->is_dhcp_enabled) {
        print "(statically overridden)";
    }
    print "\n";

    print "dhcp enabled=", $self->is_dhcp_enabled ? "Yes" : "No", "\n";
    
    my @ipaddresses = $self->get_ipaddresses;
    print "ip addresses=@ipaddresses (", scalar @ipaddresses, ") ";
    if (($self->_get_static_ipaddresses)[0] ne "0.0.0.0" && $self->is_dhcp_enabled) {
        print "(should have been statically overridden ;-) )";
    }
    print "\n";

    my @subnet_masks = $self->get_subnet_masks;
    print "subnet masks=@subnet_masks (", scalar @subnet_masks, ") ";
    if (($self->_get_static_subnet_masks)[0] ne "0.0.0.0" && $self->is_dhcp_enabled) {
        print "(statically overridden)";
    }
    print "\n";

    my @gateways = $self->get_gateways;
    print "gateways=@gateways (", scalar @gateways, ") ";
    if ($self->_get_static_gateways != 0 && $self->is_dhcp_enabled) {
        print "(statically overridden)";
    }
    print "\n";

    my @dns = $self->get_dns;
    print "dns=@dns (", scalar @dns, ") ";
    if ($self->_get_static_dns != 0 && $self->is_dhcp_enabled) {
        print "(statically overridden)";
    }
    print "\n";

    my @wins = $self->get_wins;
    print "wins=@wins (", scalar @wins, ") ";
    if ($self->_get_static_wins != 0 && $self->is_dhcp_enabled) {
        print "(statically overridden)";
    }
    print "\n";

    if ($self->is_dhcp_enabled) {
        print "dhcp server=", $self->get_dhcp_server, "\n";
        print "lease obtained=", $self->get_dhcp_lease_obtained_time, "\n";
        print "lease terminates=", $self->get_dhcp_lease_terminates_time, "\n";
    }
}

1;

__END__

=head1 NAME

Win32::IPConfig::Adapter - Windows NT/2000/XP Network Adapter IP Configuration Settings

=head1 SYNOPSIS

    print $adapter->get_id, "\n";
    print $adapter->get_description, "\n";

    if ($adapter->is_dhcp_enabled) {
        print "DHCP is enabled\n";
    } else {
        print "DHCP is not enabled\n";
    }

    @ipaddresses = $adapter->get_ipaddresses;
    print "ip addresses=@ipaddresses (", scalar @ipaddresses, ")\n";

    @subnet_masks = $adapter->get_subnet_masks;
    print "subnet masks=@subnet_masks (", scalar @subnet_masks, ")\n";

    @gateways = $adapter->get_gateways;
    print "gateways=@gateways (", scalar @gateways, ")\n";

    print "domain=", $adapter->get_domain, "\n";

    @dns = $adapter->get_dns;
    print "dns servers=@dns (", scalar @dns, ")\n";

    @wins = $adapter->get_wins;
    print "wins servers=@wins (", scalar @wins, ")\n";

=head1 DESCRIPTION

Win32::IPConfig::Adapter encapsulates the TCP/IP 
configuration settings for a Windows NT/2000/XP network adapter.

=head1 METHODS

=over 4

=item $adapter->get_id

Returns the service name where the adapter settings are stored.

=item $adapter->get_description

Returns the Network Adapter Description.

=item $adapter->is_dhcp_enabled

Returns 1 if DHCP is enabled, 0 otherwise. If DHCP is enabled, the values
returned from the get_ipaddresses, get_gateways, get_domain, 
get_dns, and get_wins methods will be retrieved from the
DHCP-specific registry keys.

=item $adapter->get_ipaddresses

Returns a list of ip addresses for this adapter.
(Returns a reference to a list in a scalar context.)

=item $adapter->get_subnet_masks

Returns a list of subnet masks for this adapter.
(Returns a reference to a list in a scalar context.)
The order of subnet masks follows the order of ip addresses, so,
for example, the 2nd subnet mask will match the 2nd ip address.

=item $adapter->get_gateways

Returns a list containing the default gateway ip addresses.
(Returns a reference to a list in a scalar context.)
If no default gateways are configured, an empty list will be returned.
Statically configured default gateways will override any assigned by DHCP.

(Bet you didn't realise Windows allowed you to have multiple
default gateways.)

=item $adapter->get_domain

Returns the connection-specific domain suffix. This is only available
on Windows 2000 and later.
A statically configured domain will override any assigned by DHCP.

(As a convenience, this will return the host-specific DNS suffix
on Windows NT machines.)

=item $adapter->get_dns

Returns a list containing DNS server ip addresses.
(Returns a reference to a list in a scalar context.)
If no DNS servers are configured, an empty list will be returned.
Statically configured DNS Servers will override any assigned by DHCP.

=item $adapter->get_wins

Returns a list containing WINS server ip addresses.
(Returns a reference to a list in a scalar context.)
If no WINS servers are configured, an empty list will be returned.
Statically configured WINS Servers will override any assigned by DHCP.

=item $adapter->set_domain($domainsuffix)

On Windows 2000/XP, sets the connection-specific DNS suffix.
On Windows NT, as a convenience, sets the host-specific DNS suffix.

You will not be allowed to set this value if the host adapter is
configured through DHCP.

On Windows NT systems, the setting appears to take effect immediately.
On Windows 2000 systems, the setting does not appear to take effect 
until the DNS Client service is restarted or the machine is rebooted.

=item $adapter->set_dns(@dnsservers)

Sets the DNS servers to @dnsservers. You can use an empty list
to remove all configured DNS servers.

You will not be allowed to set this value if the host adapter is
configured through DHCP.

On Windows NT systems, you will need to reboot for this setting to take 
effect. On Windows 2000 systems, you will need to restart the DNS Client
service or reboot the machine.

=item $adapter->set_wins(@winsservers)

Set the host's WINS servers to @winsservers, which should be a list of
contactable WINS servers on the network. You can use an empty list
to remove all configured WINS servers.

You will not be allowed to set this value if the host adapter is
configured through DHCP.

On Windows NT systems, you will need to reboot for this change to take effect.
On Windows 2000, you also appear to need to reboot the host machine.

=item $adapter->get_dhcp_server

Returns the ip address of the DHCP server that supplied the adapter's
ip address.

You will only be able to read this value if the host adapter is
configured through DHCP.

=item $adapter->get_dhcp_lease_obtained_time

Returns the lease obtained time in the format YYYY-MM-DD HH-MM.

You will only be able to read this value if the host adapter is
configured through DHCP.

=item $adapter->get_dhcp_lease_terminates_time

Returns the lease terminates time in the format YYYY-MM-DD HH-MM.

You will only be able to read this value if the host adapter is
configured through DHCP.

=back

=head1 AUTHOR

James Macfarlane, E<lt>jmacfarla@cpan.orgE<gt>

=head1 SEE ALSO

Win32::IPConfig

=cut

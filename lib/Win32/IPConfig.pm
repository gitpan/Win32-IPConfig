package Win32::IPConfig;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.01';

use Win32::TieRegistry qw/:KEY_/;
use Win32::IPConfig::Adapter;

sub new
{
    my $class = shift;

    my $host = shift || "";

    my $hklm = $Registry->Connect($host, "HKEY_LOCAL_MACHINE",
        {Access => KEY_READ})
        or return undef;

    $hklm->SplitMultis(1); # return REG_MULTI_SZ as arrays

    my $osversion = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion"}->{"CurrentVersion"};

    # Get the network parameters
    my $services = $hklm->{"SYSTEM\\CurrentControlSet\\Services"};
    my $tcpipparams = $services->{"Tcpip\\Parameters"};

    my $self = {};
    $self->{"domain"} = $tcpipparams->{"Domain"};
    $self->{"hostname"} = $tcpipparams->{"Hostname"};

    # Note that on 2000, you can switch between using
    # the primary + connection-specific domains or
    # using the searchlist. The default is to use the
    # primary + connection-specific domains.
    if ($osversion eq "5.0") {
        my @searchlist = split /,/, $tcpipparams->{"SearchList"};
        $self->{"searchlist"} = \@searchlist;
    } else {
        my @searchlist = split / /, $tcpipparams->{"SearchList"};
        $self->{"searchlist"} = \@searchlist;
    }

    # Get the NetBT information
    $self->{"nodetype"} = $services->{"Netbt\\Parameters\\NodeType"} || "";

    # Retrieve each network card's config
    my $networkcards = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\NetworkCards"};
    for my $nic ($networkcards->SubKeyNames) {
        my $adapter = Win32::IPConfig::Adapter->new($hklm, $nic);
        push @{$self->{"adapters"}}, $adapter;
    }

    $self->{"osversion"} = $osversion;
    bless $self, $class;
    return $self;
}

sub get_adapters { return $_[0]->{"adapters"}; }
sub get_osversion { return $_[0]->{"osversion"}; }
sub get_hostname { return $_[0]->{"hostname"}; }
sub get_domain { return $_[0]->{"domain"}; }
sub get_searchlist { return $_[0]->{"searchlist"}; }
sub get_nodetype { return $_[0]->{"nodetype"}; }

sub dump
{
    my $self = shift;

    print "hostname=", $self->get_hostname, "\n";
    print "domain=", $self->get_domain, "\n";
    my @searchlist = @{$self->get_searchlist};
    print "searchlist=@searchlist\n";
    print "osversion=", $self->get_osversion, "\n";
    print "nodetype=", $self->get_nodetype, "\n";
    my $i = 1;
    for (@{$self->get_adapters}) {
        print "\nCard ", $i++, ":\n";
        $_->dump;
    }
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

Win32::IPConfig - Windows NT/2000 IP Configuration Settings

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

Win32::IPConfig is a module for retrieving TCP/IP network settings from a
Windows NT/2000 host machine. Specify the host and the module will retrieve and
collate all the information from the specified machine's registry (using
Win32::TieRegistry). For this module to retrieve information from a host
machine, you must have read access to the registry on that machine.

=head1 CONSTRUCTOR

=over 4

=item $ipconfig = Win32::IPConfig->new($host);

Creates a new Win32::IPConfig object. $host is passed directly to
Win32::TieRegistry, and can be a computer name or an IP address.

=back

=head1 METHODS

=over 4

=item $ipconfig->get_hostname

Returns a string containing the DNS hostname of the machine.

=item $ipconfig->get_domain

Returns a string containing the domain name of the machine.
In the case of a Windows 2000 machine (which can have connection-specific
domain names), this is the primary domain name.

=item $ipconfig->get_nodetype

Returns the node type of the machine. Note that this is not always
there. It will default to 

    0x1 - B-node

=item $ipconfig->get_adapters

The real business of the module. Returns a reference to list of
Win32::IPConfig::Adapter objects. See the following section for more
information.

=back

=head1 EXAMPLES

=head2 Collecting IP Settings for a list of PCs

    use Win32::IPConfig;

    print "hostname,domain,dhcp?,ipaddresses,gateways,dns servers,wins servers\n";
    while (<DATA>) {
        chomp;
        $ipconfig = Win32::IPConfig->new($_);
        print $ipconfig->get_hostname, ",", $ipconfig->get_domain, ",";
        if (@adapters = @{$ipconfig->get_adapters}) {
            $adapter = $adapters[0];
            if ($adapter->is_dhcp_enabled) {
                print "Y,";
            } else {
                print "N,";
            }
            @ipaddresses = @{$adapter->get_ipaddresses};
            print "@ipaddresses,";
            @gateways = @{$adapter->get_gateways};
            print "@gateways,";
            @dns = @{$adapter->get_dns};
            print "@dns,";
            @wins = @{$adapter->get_wins};
            print "@wins";
        }
        print "\n";
    }

    __DATA__
    HOST1
    HOST2
    HOST3

=head1 REGISTRY KEYS USED

IP configuration information is stored in a number of registry keys under
HKLM\SYSTEM\CurrentControlSet\Services.

To access adapter-specific configuration information, you need the adapter id,
which can be found by examining the list of installed network cards at
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkCards.

Note that in NT the adapter id will look like a service or driver, while in
2000 it will be a GUID.

There are some variations in where Windows NT and Windows 2000 store TCP/IP
configuration data. This is shown in the following lists. Note that Windows
2000 sometimes stores data in the old location as well as the new 2000
adapter-specific location. In these cases, the module will read the data
from the new registry location.

=head2 IP Address Information

    Value: IPAddress (REG_MULTI_SZ)
    NT:    <adapter>\Parameters\Tcpip
    2000:  <adapter>\Parameters\Tcpip
    2000:  Tcpip\Parameters\Interfaces\<adapter>

    Value: SubnetMask (REG_MULTI_SZ)
    NT:    <adapter>\Parameters\Tcpip
    2000:  <adapter>\Parameters\Tcpip
    2000:  Tcpip\Parameters\Interfaces\<adapter>

    Value: DefaultGateway (REG_MULTI_SZ)
    NT:    <adapter>\Parameters\Tcpip
    2000:  <adapter>\Parameters\Tcpip
    2000:  Tcpip\Parameters\Interfaces\<adapter>

    Value: EnableDHCP (REG_DWORD)
    NT:    <adapter>\Parameters\Tcpip
    2000:  <adapter>\Parameters\Tcpip
    2000:  Tcpip\Parameters\Interfaces\<adapter>

=head2 DNS Information

    Value: Hostname (REG_SZ)
    NT:    Tcpip\Parameters
    2000:  Tcpip\Parameters

    Value: NV Hostname (REG_SZ)
    2000:  Tcpip\Parameters

    Value: Domain (REG_SZ)
    NT:    Tcpip\Parameters
    2000:  Tcpip\Parameters (primary)
    2000:  Tcpip\Parameters\Interfaces\<adapter> (connection-specific)

    Value: NameServer (REG_SZ) (a space delimited list)
    NT:    Tcpip\Parameters
    2000:  Tcpip\Parameters (although it was blank; is it used?)
    2000:  Tcpip\Parameters\Interfaces\<adapter>

    Value: SearchList (REG_SZ) (space delimited on NT, comma delimited on 2000)
    NT:    Tcpip\Parameters
    2000:  Tcpip\Parameters

=head2 WINS Information

    Value: NameServer (REG_SZ)
    NT:    Netbt\Adapters\<adapter>

    Value: NameServerBackup (REG_SZ)
    NT:    Netbt\Adapters\<adapter>

    Value: NameServerList (REG_MULTI_SZ)
    2000:  Netbt\Parameters\Interfaces\Tcpip_<adapter>

Q120642 and Q314053 talk about NameServer and NameServerBackup
existing on 2000 in the Netbt\Parameters\Interfaces\Tcpip_<adapter>
registry key, but this appears to be wrong.

    Value: NodeType (REG_DWORD)
    NT:    Netbt\Parameters
    2000:  Netbt\Parameters

=head1 AUTHOR

James Macfarlane, E<lt>jmacfarla@cpan.orgE<gt>

=head1 SEE ALSO

Win32::TieRegistry

The following Microsoft support articles were helpful:

=over 4

=item *

Q120642 TCP/IP and NBT Configuration Parameters for Windows 2000 or Windows NT

=item *

Q314053 TCP/IP and NBT Configuration Parameters for Windows XP

=back

=cut

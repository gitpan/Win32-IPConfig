package Win32::IPConfig;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.04';

use Carp;
use Win32::TieRegistry qw/:KEY_/;
use Win32::IPConfig::Adapter;

sub new
{
    my $class = shift;

    my $host = shift || "";

    my $hklm = $Registry->Connect($host, "HKEY_LOCAL_MACHINE",
        {Access => KEY_READ | KEY_WRITE})
        or return undef;

    $hklm->SplitMultis(1); # return REG_MULTI_SZ as arrays

    my $osversion = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\CurrentVersion"};

    unless ($osversion eq "4.0" || $osversion eq "5.0" || $osversion eq "5.1") {
        croak "Currently only supports Windows NT/2000/XP";
    }

    my $services = $hklm->{"SYSTEM\\CurrentControlSet\\Services"};

    my $self = {};
    $self->{"osversion"} = $osversion;

    # Remember the necessary registry keys
    $self->{"netbtparams"} = $services->{"Netbt\\Parameters"};
    $self->{"tcpipparams"} = $services->{"Tcpip\\Parameters"};

    # Retrieve each network card's config
    my $networkcards = $hklm->{"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\NetworkCards"};
    for my $nic ($networkcards->SubKeyNames) {
        if (my $adapter = Win32::IPConfig::Adapter->new($hklm, $nic)) {
            push @{$self->{"adapters"}}, $adapter;
        }
    }

    bless $self, $class;
    return $self;
}

sub get_adapters { return $_[0]->{"adapters"}; }
sub get_osversion { return $_[0]->{"osversion"}; }

sub get_hostname
{
    my $self = shift;

    return $self->{"tcpipparams"}{"Hostname"};
}

sub get_domain
{
    my $self = shift;

    return $self->{"tcpipparams"}{"Domain"};
}

sub get_searchlist
{
    my $self = shift;

    my @searchlist;
    if ($self->{"osversion"} eq "5.0" || $self->{"osversion"} eq "5.1") {
        @searchlist = split /,/, $self->{"tcpipparams"}{"SearchList"};
    } else {
        @searchlist = split / /, $self->{"tcpipparams"}{"SearchList"};
    }
    return \@searchlist;
}

sub get_nodetype
{
    my $self = shift;

    # Got a real problem here. How can I determine whether to
    # use DhcpNodeType or NodeType given that being DHCP enabled
    # is a property of an adapter, not a host?
    # So I currently settled for always reporting the statically
    # configured NodeType setting, even though this will be invalid
    # if there are DHCP adapters.

    my %nodetypes = (1=>"B-node", 2=>"P-node", 4=>"M-node", 8=>"H-node");
    my $nodetype;
    if ($nodetype = $self->{"netbtparams"}{"NodeType"}) {
        $nodetype = hex($nodetype);
        return $nodetypes{$nodetype};
    } else {
        return "";
    }
}

sub is_router
{
    my $self = shift;

    if (my $router = $self->{"tcpipparams"}{"IPEnableRouter"}) {
        return hex($router);
    } else {
        return 0; # defaults to 0
    }
}

sub is_wins_proxy
{
    my $self = shift;

    if (my $proxy = $self->{"netbtparams"}{"EnableProxy"}) {
        return hex($proxy);
    } else {
        return 0; # defaults to 0
    }
}

sub is_lmhosts_enabled
{
    my $self = shift;

    if (my $lmhosts_enabled = $self->{"netbtparams"}{"EnableLMHOSTS"}) {
        return hex($lmhosts_enabled);
    } else {
        return 1; # defaults to 1
    }
}

sub get_adapter
{
    my $self = shift;
    my $adapter_num = shift;

    my $adapter = ${$self->{"adapters"}}[$adapter_num];
    return $adapter;
}

sub dump
{
    my $self = shift;

    print "hostname=", $self->get_hostname, "\n";
    print "domain=", $self->get_domain, "\n";
    my @searchlist = @{$self->get_searchlist};
    print "searchlist=@searchlist\n";
    print "nodetype=", $self->get_nodetype, "\n";
    print "ip routing enabled=", $self->is_router ? "Yes":"No", "\n";
    print "wins proxy enabled=", $self->is_wins_proxy ? "Yes":"No", "\n";
    print "LMHOSTS enabled=", $self->is_lmhosts_enabled ? "Yes":"No", "\n";
    my $i = 1;
    for (@{$self->get_adapters}) {
        print "\nCard ", $i++, ":\n";
        $_->dump;
    }
}

1;

# IP Address Information

# Value:   IPAddress (REG_MULTI_SZ)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   SubnetMask (REG_MULTI_SZ)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   DefaultGateway (REG_MULTI_SZ)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   IPEnableRouter (REG_DWORD)
# NT:      Tcpip\Parameters
# 2000/XP: Tcpip\Parameters

# Value:   EnableDHCP (REG_DWORD)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   DhcpIPAddress (REG_SZ)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   DhcpSubnetMask (REG_SZ)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   DhcpDefaultGateway (REG_MULTI_SZ)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   DhcpServer (REG_SZ)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   LeaseObtainedTime (REG_DWORD)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   LeaseTerminatesTime (REG_DWORD)
# NT:      <adapter>\Parameters\Tcpip
# 2000/XP: <adapter>\Parameters\Tcpip
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# DNS Information

# Value:   Hostname (REG_SZ)
# NT:      Tcpip\Parameters
# 2000/XP: Tcpip\Parameters

# Value:   NV Hostname (REG_SZ)
# 2000/XP: Tcpip\Parameters

# Value:   Domain (REG_SZ)
# NT:      Tcpip\Parameters
# 2000/XP: Tcpip\Parameters (primary)
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter> (connection-specific)

# Value:   NV Domain (REG_SZ)
# 2000/XP: Tcpip\Parameters

# Value:   NameServer (REG_SZ) (a space delimited list)
# NT:      Tcpip\Parameters
# 2000/XP: Tcpip\Parameters (although it was blank; is it used?)
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   SearchList (REG_SZ) (space delimited on NT, comma delimited on 2000)
# NT:      Tcpip\Parameters
# 2000/XP: Tcpip\Parameters

# Value:   DhcpDomain (REG_SZ)
# NT:      *still to be determined*
# 2000/XP: Tcpip\Parameters
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# Value:   DhcpNameServer (REG_SZ) (a space delimited list)
# NT:      Tcpip\Parameters
# 2000/XP: Tcpip\Parameters (same as below)
# 2000/XP: Tcpip\Parameters\Interfaces\<adapter>

# WINS Information

# Value:   NameServer (REG_SZ)
# NT:      Netbt\Adapters\<adapter>

# Value:   NameServerBackup (REG_SZ)
# NT:      Netbt\Adapters\<adapter>

# Value:   NameServerList (REG_MULTI_SZ)
# 2000/XP: Netbt\Parameters\Interfaces\Tcpip_<adapter>

# Value:   DhcpNameServer (REG_SZ)
# NT:      Netbt\Adapters\<adapter>

# Value:   DhcpNameServerBackup (REG_SZ)
# NT:      Netbt\Adapters\<adapter>

# Value:   DhcpNameServerList (REG_MULTI_SZ)
# 2000/XP: Netbt\Parameters\Interfaces\Tcpip_<adapter>

# Q120642 and Q314053 talk about NameServer and NameServerBackup
# existing on 2000 in the Netbt\Parameters\Interfaces\Tcpip_<adapter>
# registry key, but this appears to be wrong.

# Value:   NodeType (REG_DWORD)
# NT:      Netbt\Parameters
# 2000/XP: Netbt\Parameters

# Value:   DhcpNodeType (REG_DWORD) (overidden by NodeType)
# NT:      Netbt\Parameters
# 2000/XP: Netbt\Parameters

# Value:   EnableProxy (REG_DWORD)
# NT:      Netbt\Parameters
# 2000/XP: Netbt\Parameters

# Value:   EnableLMHOSTS (REG_DWORD)
# NT:      Netbt\Parameters
# 2000/XP: Netbt\Parameters

__END__

=head1 NAME

Win32::IPConfig - Windows NT/2000/XP IP Configuration Settings

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
Windows NT/2000/XP host machine. Specify the host and the module will retrieve
and collate all the information from the specified machine's registry (using
Win32::TieRegistry). For this module to retrieve information from a host
machine, you must have read and write access to the registry on that machine.

=head1 METHODS

=over 4

=item $ipconfig = Win32::IPConfig->new($host);

Creates a new Win32::IPConfig object. $host is passed directly to
Win32::TieRegistry, and can be a computer name or an IP address.

=item $ipconfig->get_hostname

Returns a string containing the DNS hostname of the machine.

=item $ipconfig->get_domain

Returns a string containing the domain name of the machine.
For Windows 2000/XP machines (which can have connection-specific
domain names) this is the primary domain name.

=item $ipconfig->get_nodetype

Returns the node type of the machine. Note that this is not always
present. It will default to 0x1 B-node if no WINS servers are configured,
and default to 0x8 H-node if there are. The four possible node types are:

    B-node - resolve NetBIOS names by broadcast
    P-node - resolve NetBIOS names using a WINS server
    M-node - resolve NetBIOS names by broadcast, then using a WINS server
    H-node - resolce NetBIOS names using a WINS server, then by broadcast

Currently this value is only reliable on statically configured hosts.
Do not rely on this value if you have DHCP enabled adapters.

=item $ipconfig->get_adapters

The real business of the module. Returns a reference to list of
Win32::IPConfig::Adapter objects. See the Adapter documentation
for more information.

=item $ipconfig->get_adapter($num)

Returns the Win32::IPConfig::Adapter specified by $num. Use
$ipconfig->get_adapter(0) to retrieve the first adapter.

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

=head2 Setting a PC's DNS servers

    use Win32::IPConfig;

    my $host = shift;
    my $ipconfig = Win32::IPConfig->new($host);
    my @dns = @ARGV;
    my $adapter = $ipconfig->get_adapter(0);
    $adapter->set_dns(@dns);

=head1 REGISTRY KEYS USED

IP configuration information is stored in a number of registry keys under
HKLM\SYSTEM\CurrentControlSet\Services.

To access adapter-specific configuration information, you need the adapter id,
which can be found by examining the list of installed network cards at
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkCards.

Note that in NT the adapter id will look like a service or driver, while in
2000/XP it will be a GUID.

There are some variations in where Windows NT and Windows 2000/XP store TCP/IP
configuration data. This is shown in the following lists. Note that Windows
2000/XP sometimes stores data in the old adapter-specific location as well as
the new 2000/XP adapter-specific location. In these cases, the module will read
the data from the new registry location.

For all operating systems, the main keys are:

    Tcpip\Parameters
    Netbt\Parameters

Adapter-specific settings are stored in:

    <adapter>\Parameters\Tcpip (Windows NT)
    Tcpip\Parameters\Interfaces\<adapter> (Windows 2000/XP)

NetBIOS over TCP/IP stores adapter-specific settings in:

    Netbt\Adapters\<adapter> (on Windows NT)
    Netbt\Parameters\Interfaces\Tcpip_<adapter> (on Windows 2000/XP)

=head1 NOTES

Note that Windows 2000 and later will use its DNS server setting to resolve
Windows computer names, whereas Windows NT will use its WINS server
settings first.

For Windows 2000 and later, both the primary and connection-specific domain
settings are significant and will be used in this initial name 
resolution process.

The DHCP Server options correspond to the following registry values:

    003 Router              ->  DhcpDefaultGateway
    006 DNS Servers         ->  DhcpNameServer
    015 DNS Domain Name     ->  DhcpDomain
    044 WINS/NBNS Servers   ->  DhcpNameServer/DhcpNameServerList
    046 WINS/NBT Node Type  ->  DhcpNodeType

=head1 AUTHOR

James Macfarlane, E<lt>jmacfarla@cpan.orgE<gt>

=head1 SEE ALSO

Win32::IPConfig::Adapter

Win32::TieRegistry

The following Microsoft support articles were helpful:

=over 4

=item *

Q120642 TCP/IP and NBT Configuration Parameters for Windows 2000 or Windows NT

=item *

Q314053 TCP/IP and NBT Configuration Parameters for Windows XP

=back

=cut

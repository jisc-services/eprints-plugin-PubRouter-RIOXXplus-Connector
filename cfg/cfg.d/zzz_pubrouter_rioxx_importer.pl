#Enable the plugin
$c->{plugins}->{"Import::PubRouter"}->{params}->{disable} = 0;

#Ensure Atom export plugin is enabled for SWORD responses
$c->{plugins}->{"Export::Atom"}->{params}->{disable} = 0;

#allow documents to be imported via URL
$c->{enable_web_imports} = 1;

#PubRouter API key for importing document via URL supplied by PubRouter
$c->{plugins}{"Import::PubRouter"}{params}{api_key} = "ENTER PUBROUTER API KEY HERE";

$c->{rioxx2}->{license_map} = {
        cc_by_nd        => "http://creativecommons.org/licenses/by-nd/3.0",
        cc_by           => "http://creativecommons.org/licenses/by/3.0",
        cc_by_nc        => "http://creativecommons.org/licenses/by-nc/3.0",
        cc_by_nc_nd     => "http://creativecommons.org/licenses/by-nc-nd/3.0",
        cc_by_nc_sa     => "http://creativecommons.org/licenses/by-nd-sa/3.0",
        cc_by_sa        => "http://creativecommons.org/licenses/by-sa/3.0",
        cc_public_domain=> "http://creativecommons.org/publicdomain/zero/1.0/legalcode",
        cc_gnu_gpl      => "http://www.gnu.org/licenses/gpl.html",
        cc_gnu_lgpl     => "http://www.gnu.org/licenses/lgpl.html",
	cc_by_nd_4      => "http://creativecommons.org/licenses/by-nd/4.0",
        cc_by_4         => "http://creativecommons.org/licenses/by/4.0",
        cc_by_nc_4      => "http://creativecommons.org/licenses/by-nc/4.0",
        cc_by_nc_nd_4   => "http://creativecommons.org/licenses/by-nc-nd/4.0",
        cc_by_nc_sa_4   => "http://creativecommons.org/licenses/by-nd-sa/4.0",
        cc_by_sa_4      => "http://creativecommons.org/licenses/by-sa/4.0",
};


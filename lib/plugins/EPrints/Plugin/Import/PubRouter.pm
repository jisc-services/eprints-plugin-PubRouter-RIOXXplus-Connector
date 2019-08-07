=head1 NAME

    Jisc PubRouter RIOXX importer
    Copyright (C) 2017  Jisc

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see < https://www.gnu.org/licenses/lgpl.txt>.

=cut

package EPrints::Plugin::Import::PubRouter;

use strict;

use EPrints::Plugin::Import::DefaultXML;
use LWP::Simple;

our @ISA = qw/ EPrints::Plugin::Import::DefaultXML /;

my %namespaces =
	(
		'ali' => 'http://www.niso.org/schemas/ali/1.0/',
		'dcterms' => 'http://purl.org/dc/terms/',
		'rioxxterms' => 'http://www.rioxx.net/schema/v2.0/rioxx/',
		'pr' => 'http://pubrouter.jisc.ac.uk/rioxxplus/v2.0/',
	);

my %types =
	(
		'Journal Article' => 'article',
		'Book' => 'book',
		'Book chapter' => 'book_section',
		'Book edited' => 'book_section',
		'Conference Paper/Proceeding/Abstract' => 'conference_item',
		'Journal Article/Review' => 'article',
		'Manual/Guide' => 'monograph',
		'Monograph' => 'monograph',
		'Policy briefing report' => 'monograph',
		'Technical Report' => 'monograph',
		'Technical Standard' => 'monograph',
		'Thesis' => 'thesis',
		'Other' => 'other',
		'Consultancy Report' => 'monograph',
		'Working paper' => 'monograph',
	);

my %monograph_types =
	(
		'Manual/Guide' => 'manual',
		'Policy briefing report' => 'other',
		'Technical Report' => 'technical_report',
		'Technical Standard' => 'technical_report',
		'Consultancy Report' => 'project_report',
		'Working paper' => 'working_paper',
	);

my %content = 
	(
		'AO' => 'draft',
		'SMUR' => 'submitted',
		'AM' => 'accepted',
		'VoR' => 'published',
		'CVoR' => 'updated',
		'EVoR' => 'updated',
	);

my %license_urls = 
	(
		"creativecommons.org/licenses/by-nd/3.0/" => 'cc_by_nd',
		"creativecommons.org/licenses/by/3.0/" => 'cc_by',
		"creativecommons.org/licenses/by-nc/3.0/" => 'cc_by_nc',
		"creativecommons.org/licenses/by-nc-nd/3.0/" => 'cc_by_nc_nd',
		"creativecommons.org/licenses/by-nd-sa/3.0/" => 'cc_by_nc_sa',
		"creativecommons.org/licenses/by-sa/3.0/" => 'cc_by_sa',
		"creativecommons.org/licenses/by-nd/4.0/" => 'cc_by_nd_4',
		"creativecommons.org/licenses/by/4.0/" => 'cc_by_4',
		"creativecommons.org/licenses/by-nc/4.0/" => 'cc_by_nc_4',
		"creativecommons.org/licenses/by-nc-nd/4.0/" => 'cc_by_nc_nd_4',
		"creativecommons.org/licenses/by-nd-sa/4.0/" => 'cc_by_nc_sa_4',
		"creativecommons.org/licenses/by-sa/4.0/" => 'cc_by_sa_4',
		"creativecommons.org/publicdomain/zero/1.0/legalcode/" => 'cc_public_domain',
		"www.gnu.org/licenses/gpl.html" => 'cc_gnu_gpl',
		"www.gnu.org/licenses/lgpl.html" => 'cc_gnu_lgpl',
	);

sub new
{
        my( $class, %params ) = @_;

        my $self = $class->SUPER::new(%params);

        $self->{name} = "Jisc PubRouter RIOXX importer";
        $self->{visible} = "all";
        $self->{produce} = [ 'list/eprint', 'dataobj/eprint' ];
	$self->{accept} = [ qw( application/atom+xml application/vnd.rioxx2.data+xml ) ];

        return $self;
}

sub input_fh
{
        my( $plugin, %opts ) = @_;
   
        my $fh = $opts{"fh"};

	my @keys = keys %opts;
 
      	my $xml = join "", <$fh>;

        my $list;

        if( $xml =~ /^<\?xml/ )
       	{
                $list = $plugin->input_fh_xml( $xml, %opts );
       	}

        $list ||= EPrints::List->new(
       	        dataset => $opts{dataset},
               	session => $plugin->{session},
                ids => [] );

        return $list;
}

sub input_fh_xml
{
	my( $plugin, $xml, %opts ) = @_;

	my $doc = EPrints::XML::parse_xml_string( $xml );

	my $node = $doc->documentElement;
	my @ns = $node->getNamespaces;
	my $pr_uri = $node->lookupNamespaceURI( "pr" );
	if( $pr_uri ne "http://pubrouter.jisc.ac.uk/rioxxplus/v2.0/" )
	{
		die "Wrong version of XML received, expecting xmlns:pr=\"http://pubrouter.jisc.ac.uk/rioxxplus/v2.0/\" got xmlns:pr=\"$pr_uri\"";
	}
	else
	{
		my $dataobj = $plugin->xml_to_dataobj( $opts{dataset}, $doc->documentElement );	
		EPrints::XML::dispose( $doc );
		return EPrints::List->new(
			dataset => $opts{dataset},
			session => $plugin->{session},
			ids => [defined($dataobj) ? $dataobj->get_id : ()] 
		);
	}
}

sub xml_to_epdata
{
        my( $plugin, $dataset, $xml ) = @_;
	
        my $session = $plugin->{session};

        my $epdata = {};
	my $docdata = {};

	#note
	my @notes = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'note' );
	foreach my $n ( @notes )
	{
		$epdata->{note} = $epdata->{note} . $plugin->xml_to_text( $n );	
	}

	#comment
	$epdata->{suggestions} = $plugin->getNameSpaceValue( $xml, $namespaces{'pr'}, 'comment' );

	#subjects
	my @subjects = $xml->getElementsByTagNameNS( $namespaces{'dcterms'}, 'subject' );
	my @keywords;
	foreach my $s( @subjects )
	{
		push @keywords, $plugin->xml_to_text( $s );
	}
	$epdata->{keywords} = join( ", ", @keywords );

	#related urls
	my @relations = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'relation' );
	$epdata->{related_url} = [];
	foreach my $r( @relations )
	{
		push @{$epdata->{related_url}}, {
			url => $r->getAttribute( "url" ),
			type => $plugin->xml_to_text( $r ),
		}
	};

	#type
	my $type = $plugin->getNameSpaceValue( $xml, $namespaces{'rioxxterms'}, 'type' );	
	if( $type eq "" )
	{
		$type = $plugin->getNameSpaceValue( $xml, $namespaces{'dcterms'}, 'type' );
	}
	$epdata->{type} = $types{$type} if defined $type;
	$epdata->{type} ||= 'other';
	
	#source, volume and number
	my $source = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'source')->item(0);
	if( defined $source )
	{
		if( $epdata->{type} eq "book_section" )
		{
			$epdata->{book_title} = $plugin->xml_to_text( $source );
		}
		else
		{
			$epdata->{publication} = $plugin->xml_to_text( $source );
		}
		$epdata->{volume} = $source->getAttribute( "volume" ) if defined $source;
		$epdata->{number} = $source->getAttribute( "issue" ) if defined $source;
	}
 
	#source id
	my @sourceids = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'source_id');	
	my $issn_set = 0;
	foreach my $sourceid (@sourceids)
	{
		my $sourceid_type = $sourceid->getAttribute( "type" );
		if( $sourceid_type eq "eissn" )
		{
			$epdata->{issn} = $plugin->xml_to_text( $sourceid );
			$issn_set = 1; #used to prioritise eissn value
		}
		elsif( !$issn_set && ( $sourceid_type eq "issn" || $sourceid_type  eq "pissn" ) )
		{
			$epdata->{issn} = $plugin->xml_to_text( $sourceid );
		}
		elsif( $sourceid_type eq "isbn" )
		{
			$epdata->{isbn} = $plugin->xml_to_text( $sourceid );
		}	
	}

	#publisher
	$epdata->{publisher} = $plugin->getNameSpaceValue( $xml, $namespaces{'dcterms'}, 'publisher' );

	#title
	$epdata->{title} = $plugin->getNameSpaceValue( $xml, $namespaces{'dcterms'}, 'title' );

	#if monograph work out the monograph type
	if( $epdata->{type} eq "monograph" )
	{
		$epdata->{monograph_type} = $monograph_types{$type};	
	}	

	#version
	my $version = $plugin->getNameSpaceValue( $xml, $namespaces{'rioxxterms'}, 'version' );	
	if( $version ne "" )
	{
		my $c = $content{$version};
		$docdata->{content} = $c if defined $c;
	};

	#page range
	my $pagerange = $plugin->getNameSpaceValue( $xml, $namespaces{'pr'}, 'page_range' );
	$epdata->{pagerange} = $pagerange;

	if( !defined $epdata->{pagerange} )
	{
		$epdata->{pagerange} = $plugin->getNameSpaceValue( $xml, $namespaces{'pr'}, 'start_page' );
		
		my $end_page = $plugin->getNameSpaceValue( $xml, $namespaces{'pr'}, 'end_page' );
		$epdata->{pagerange} = $epdata->{pagerange} . '-' . $end_page if( defined $end_page && defined $epdata->{pagerange} ); 
	}

	#pages
	my $pages = $plugin->getNameSpaceValue( $xml, $namespaces{'pr'}, 'num_pages' );
	$epdata->{pages} = $pages if($pages =~ /^\d+$/);

	#language
	my $code = $plugin->getNameSpaceValue( $xml, $namespaces{'dcterms'}, 'language' );
	if( length $code > 2 )
	{
		$code = "en"; #assume english
 	}
	$docdata->{language} = $code;

	#description
        $epdata->{abstract} = $plugin->getNameSpaceValue( $xml, $namespaces{'dcterms'}, 'abstract' );

	#identifier
	my @identifiers = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'identifier' );
	foreach my $id (@identifiers)
	{
		my $identifier_type = $id->getAttribute( "type" );
                $epdata->{id_number} = $plugin->xml_to_text( $id );
                # Break from loop if DOI is found, otherwise the id_number of this eprint will be the last in the list
                last if( $identifier_type eq "doi" );
        }

	#version_of_record
	my $vor = $plugin->getNameSpaceValue( $xml, $namespaces{'rioxxterms'}, 'version_of_record' );
	$epdata->{id_number} = $vor if $vor ne "";

	#dateAccepted
	my $acceptance_set = 0;
	my $acceptance_date = $plugin->getNameSpaceValue( $xml, $namespaces{'dcterms'}, 'dateAccepted' );
	if( $acceptance_date )
	{
		my ( $year, $month, $day ) = split /-/, $acceptance_date;
		if( $dataset->has_field( "dates" ) )
                {
                        $epdata->{dates} ||= [];
                        push @{$epdata->{dates}}, { 
                                date => $acceptance_date,
                                date_type => "accepted",
                        };
			$acceptance_set = 1;
                }
		elsif( $dataset->has_field( "rioxx2_dateAccepted_input" ) )
		{
			$epdata->{rioxx2_dateAccepted_input} = $acceptance_date;
		}
	}

	#publication date
	#if DatesDatesDates is present use that...
	my $publication_set = 0;
	my $publication_date = $plugin->getNameSpaceValue( $xml, $namespaces{'rioxxterms'}, 'publication_date' );
	if( $publication_date )
	{
		my ( $year, $month, $day ) = split /-/, $publication_date;
		if( $dataset->has_field( "dates" ) )
		{
			$epdata->{dates} ||= [];
			push @{$epdata->{dates}}, { 
				date =>	$publication_date,
				date_type => "published",
			};
			$publication_set = 1;
		}
		else #use ordinary date field
		{
			$epdata->{date} = $publication_date;
			$epdata->{date_type} = "published";
			$publication_set = 1;
		}
	}

	#history dates
	my @dates = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'history_date' );
	foreach my $date ( @dates )
	{	
		my $d = $plugin->xml_to_text( $date );
		my ( $year, $month, $day ) = split /-/, $d;
		my $date_type = $date->getAttribute( "type" );

		# add a history date to the record's date field if an acceptance date or publication date hasn't been set previously
		if( ! ( ($date_type eq "accepted" && $acceptance_set) || ($date_type eq "published" && $publication_set ) ) )
		{
			if( $dataset->has_field( "dates" ) ) #the datesdatesdates plugin is likely installed
			{
				my $dates_field = $dataset->field( "dates_date_type" );
				my $types = $dates_field->property( "options" );
				if( grep { $date_type eq $_ } @{$types} ) #check the date type we're importing is one of the ones available to the datesdatesdates field
				{
					$epdata->{dates} ||= [];
					push @{$epdata->{dates}}, { 
						date =>	$d,
						date_type => $date_type,
					};
				}			
			}
			elsif( grep { $date_type eq $_ } @{$dataset->field( "date_type" )->property( "options" )} ) #we're using the regular eprint field, but first check to see if we can store this date type
			{
				$epdata->{date} = $d;
                	        $epdata->{date_type} = $date_type;
			}
		}	
	}

	#status
	if( $publication_set )
	{
		$epdata->{ispublished} = "pub";
	}

	#project and funders
	$epdata->{projects} = []; 
	$epdata->{funders} = []; 
	my @projects = $xml->getElementsByTagNameNS( $namespaces{rioxxterms}, "project" );
	foreach my $project (@projects)
	{
		#set project value
		my $project_id = $plugin->xml_to_text( $project );
		if( defined $project_id )
		{
			push @{$epdata->{projects}}, $project_id;
		}

		#funder names
		my $funder_name = $project->getAttribute( "funder_name" );
		if( defined $project_id )
		{
			if( defined $funder_name )
			{
				push @{$epdata->{funders}}, $funder_name;
			}
		}

		#RIOXX and funder ids
		my @funder_ids = split /; /, $project->getAttribute( "funder_id" );		
		foreach my $funder_id ( @funder_ids )
		{
			#remove label from funder id
			$funder_id = substr $funder_id, index( $funder_id, ":" ) + 1;
		
			if( $dataset->has_field( "rioxx2_project_input" ) )
			{
				$epdata->{rioxx2_project_input} ||= [];
				push @{$epdata->{rioxx2_project_input}}, {
					project => $project_id,
					funder_name => $funder_name,
					funder_id => $funder_id,
				};
			}
		}
	}

	#license
	my $license = $xml->getElementsByTagNameNS( $namespaces{ali}, "license_ref" )->item(0);
	if( $license && $dataset->has_field( "rioxx2_license_ref_input" ) )
	{
		my $license_url = $plugin->xml_to_text( $license );
		my $start_date = $license->getAttribute( "start_date" );
		$epdata->{rioxx2_license_ref_input} = {
                        license_ref => $license_url,
                        start_date => $start_date,
                };

		my $stripped_lic_url = $license_url;
		$stripped_lic_url =~ s/^https?:\/\///i;    # Remove 'http://' or 'https://' prefix
		if( exists $license_urls{$stripped_lic_url } )
                {
               	        $docdata->{license} = $license_urls{$stripped_lic_url};
	        }               
	}

	#embargo date
	my $embargo = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'embargo' )->item(0);
	if( $embargo )
	{
		my $embargo_start_date = $embargo->getAttribute( "start_date" );
		my $embargo_end_date = $embargo->getAttribute( "end_date" );
		my $duration = $embargo->getAttribute( "duration" );
		if( $embargo_end_date )
		{
			$docdata->{date_embargo} = $embargo_end_date;
			$docdata->{security} = "staffonly";
		}
	}	

	#authors
	$epdata->{creators} = [];
	$epdata->{corp_creators} = [];
	my @creators = $xml->getElementsByTagNameNS(  $namespaces{'pr'}, 'author' );
	foreach my $creator (@creators)
	{
		my $creatordata = {};		

		#id
		my @creator_ids = $creator->getElementsByTagNameNS( $namespaces{'pr'}, 'id' );
		foreach my $creator_id (@creator_ids)
		{
			my $creator_id_type = $creator_id->getAttribute( "type" );
			if($creator_id_type eq "orcid" && $dataset->has_field( "creators_orcid" ) )
			{
				$creatordata->{orcid} = $plugin->xml_to_text( $creator_id );
			}
		}

		#email
		$creatordata->{id} = $plugin->getNameSpaceValue( $creator, $namespaces{'pr'}, 'email' );

		#name
		my $creatorname = {};
		$creatorname->{family} = $plugin->getNameSpaceValue( $creator, $namespaces{'pr'}, 'surname' );
		$creatorname->{given} = $plugin->getNameSpaceValue( $creator, $namespaces{'pr'}, 'firstnames' );
		$creatorname->{honourific} = $plugin->getNameSpaceValue( $creator, $namespaces{'pr'}, 'suffix' );		
		$creatordata->{name} = $creatorname;

		push @{$epdata->{creators}}, $creatordata;

		#org_name
		my $org_name = $plugin->getNameSpaceValue( $creator, $namespaces{'pr'}, 'org_name' );
		push @{$epdata->{corp_creators}}, $org_name if defined $org_name;
	}

	#contributors
	$epdata->{contributors} = [];
	my @contributors = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'contributor' );
	foreach my $contributor	(@contributors)
	{
		#type
		my $contributordata = {};
		$contributordata->{type} = $plugin->getNameSpaceValue( $contributor, $namespaces{'pr'}, 'type' );
	
		#id
		my @contributor_ids = $contributor->getElementsByTagNameNS( $namespaces{'pr'}, 'id' );
		foreach my $contributor_id (@contributor_ids)
		{
			my $contributor_id_type = $contributor_id->getAttribute( "type" );
			if($contributor_id_type eq "orcid" && $dataset->has_field( "contributors_orcid" ) )
			{
				$contributordata->{orcid} = $plugin->xml_to_text( $contributor_id );
			}
		}

		#email
                $contributordata->{id} = $plugin->getNameSpaceValue( $contributor, $namespaces{'pr'}, 'email' );

		#name
		my $contributorname = {};
		$contributorname->{family} = $plugin->getNameSpaceValue( $contributor, $namespaces{'pr'}, 'surname' );
		$contributorname->{given} = $plugin->getNameSpaceValue( $contributor, $namespaces{'pr'}, 'firstnames' );
		$contributorname->{honourific} = $plugin->getNameSpaceValue( $contributor, $namespaces{'pr'}, 'suffix' );		
		$contributordata->{name} = $contributorname;

		push @{$epdata->{contributors}}, $contributordata;

		#org_name
		my $org_name = $plugin->getNameSpaceValue( $contributor, $namespaces{'pr'}, 'org_name' );
		push @{$epdata->{corp_creators}}, $org_name if defined $org_name;
	}

	####OLD####	
	#apc
	#if( $dataset->has_field( "rioxx2_apc_input" ) )
	#{
	#	$epdata->{rioxx2_apc_input} = $plugin->getNameSpaceValue( $xml, $namespaces{'rioxxterms'}, 'apc' );
	#	
	#}

	
	#coverage
	#if( $dataset->has_field( "rioxx2_coverage_input" ) )
	#{
	#	$epdata->{rioxx2_coverage_input} = [];
	#       my @coverage = $xml->getElementsByTagNameNS(  $namespaces{'dc'}, 'coverage' );
	#       foreach my $coverage (@coverage)
        #	{
	#               push @{$epdata->{rioxx2_coverage_input}}, $plugin->xml_to_text( $coverage );
        #	}
	#}

	#dateSubmitted (not official RIOXX)
	#my $submission_date = $plugin->getNameSpaceValue( $xml, $namespaces{'dcterms'}, 'dateSubmitted' );
	#if( $submission_date  && $dataset->has_field( "dates" ) )
	#{
	#	$submission_date =~ /(^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1]))/;
        #       $epdata->{dates} ||= [];
        #       push @{$epdata->{dates}}, { 
        #        	date => $1,
        #               date_type => "submitted",
        #        };
        #}

	#source
	#$epdata->{book_title} = $source;
	#$epdata->{event_title} = $source;
	
	#use Data::Dumper;
	#my $url="http://citations.eprints-hosting.org/124095/14/hello.pdf";
	#my $tmp_file = new File::Temp;
	#EPrints::Utils::wget( $session, $url, $tmp_file );
	#seek($tmp_file,0,0);
	#my $size = (-s $tmp_file);
	#print STDERR "size.....>$size\n";

	#documents...
	#$epdata->{documents} = [];

	#add XML as a document
	#my $tmp_file = new File::Temp;
	#binmode($tmp_file, ":utf8");
	#print $tmp_file $session->xml->to_string( $xml );
	#seek($tmp_file,0,0);

	#push @{$epdata->{documents}}, {
	#	mime_type => 'application/pdf',
	#	main => 'hello.pdf',
	#	files => [{
	#		filename => 'hello.pdf',
	#		filesize => (-s $tmp_file),
	#		mime_type => 'application/pdf',
	#		_content => $tmp_file,
	#	}],	
	#};
	
	#loop through all the download links, processing those marked as primary first
	#and merge in exsiting docdata retrieved from the metadata for each new document where appropriate
	my @documents = $xml->getElementsByTagNameNS( $namespaces{'pr'}, 'download_link' );
	my @ordered_links;
	my @secondary;
	foreach my $doc ( @documents )
	{
		if( $doc->getAttribute( "primary" ) eq "true" )
		{
			push @ordered_links, $doc;
		}
		else
		{	
			push @secondary, $doc;
		}
	}

        # Append secondary links to the primary set
        push @ordered_links, @secondary;

	# Now process ordered links
	foreach my $doc ( @ordered_links )
	{
		my $document = {};
		if( $doc->getAttribute( "set_details" ) eq "true" )
		{
			$document = $docdata; #copy existing document metadata for this URL		
		}

		my $docFile = $plugin->getDocData( $session, $doc );
		if( $docFile )
		{
			$document->{language} = $code;
			my %merge = ( %{$docFile}, %{$document} ); #merge doc information with new file
	
			if( $merge{mime_type} eq "application/zip" )
			{
				$merge{content} = "other";
			}
			push @{$epdata->{documents}}, \%merge;
		}
	}
	
        return $epdata;
}

sub getDocData
{
	my( $plugin, $session, $doc ) = @_;

	#get document metadata from the XML
	my $desc = $plugin->xml_to_text( $doc );
	my $public = $doc->getAttribute( "public" );
	my $url = $doc->getAttribute( "url" );
	if( ! (defined $public && $public eq "true" ) )
	{
		$url .= "?api_key=" . $plugin->param("api_key");
	}

	#check url resolves
	my $ua = LWP::UserAgent->new;
	$ua->timeout(10);
	if (head($url))	#URL resolves to something
	{
		#add metadata and file to the document
		my $filename = $doc->getAttribute( "filename" );
		my $mime_type = $doc->getAttribute( "format" );

		my $format = "text";
		if( $mime_type eq "application/zip" )
		{	
			$format = "archive";
		}

		#download the file
	       	my $tmp_file = new File::Temp;
		my $r = EPrints::Utils::wget( $session, $url, $tmp_file );
	
		#check we haver managed to access the file, if we can't access the file abort the whole process
		if( !$r->is_success )
		{
			die "Error retrieving $url";
		}
		seek($tmp_file,0,0);

		my $docdata = {
			format => $format,
			mime_type => $mime_type,
			main => $filename,
			files => [{
				filename => $filename,
				mime_type => $mime_type,
				filesize => (-s $tmp_file),
				_content => $tmp_file,
			}],     
		};
		return $docdata;
	}
	else #URL doesn't resolve
	{
		return 0;
	}
}

sub getNameSpaceValue
{
	my( $plugin, $xml, $ns, $field ) = @_;
        my $value = $xml->getElementsByTagNameNS( $ns, $field )->item(0);

	return $plugin->xml_to_text( $value ) if defined $value;
}

sub processName #return an array of names with the family name at the end of the array
{
	my( $plugin, $name ) = @_;
	
	#process names accroding to http://www.rioxx.net/profiles/v2-0-final/
	my @names = split(', ', $name);
	push @names, shift @names;
	return \@names if scalar @names > 1;

	#else try format used at https://github.com/JiscPER/jper-sword-out/blob/develop/docs/system/XWALK.md
	@names = split(' ', $name);
	return \@names if scalar @names > 1;
}

1;
	
=head1 COPYRIGHT

=for COPYRIGHT BEGIN

Copyright 2000-2011 University of Southampton.

=for COPYRIGHT END

=for LICENSE BEGIN

This file is part of EPrints L<http://www.eprints.org/>.

EPrints is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EPrints is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public
License along with EPrints.  If not, see L<http://www.gnu.org/licenses/>.

=for LICENSE END


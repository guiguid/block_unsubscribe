#!/usr/bin/env perl

#Before running the sample script please install the following modules from CPAN
# like : cpan install Mail::IMAPClient MIME::Parser HTML::TreeBuilder::XPath LWP::Simple HTML::Tree Regexp::Common Getopt::Long Browser::Open

# Always be safe
use strict;
use warnings;

# Use the module
use Mail::IMAPClient;
use MIME::Parser;
use HTML::TreeBuilder::XPath;
use LWP::Simple qw($ua get); 
use HTML::Tree;
use Regexp::Common qw /URI/;
use Getopt::Long;
use Browser::Open qw( open_browser );
use Encode qw/encode decode/;
use Data::Dumper;  
use constant {
 MULTIPART => "MULTIPART",
 TEXT => "TEXT"
};


my $num_args = $#ARGV + 1;
if ($num_args < 1) {
    print "\n Usage: ".$0." --user user --server server [--password password] [--port 993] [--nossl] [--uid] [--ext_limit 10] [--dir INBOX] \n\n\n";
    exit;
}



my $user;
my $password;
my $server;
my $port=993;
my $ssl=1;
my $uid=0;
my $external_limit=30;
my $folder='INBOX';
my $debug=0;

Getopt::Long::GetOptions( 'user=s' => \$user,
			'password:s' => \$password,
			'server=s' => \$server,
			'port:i' => \$port,
			'ssl!' => \$ssl,
			'uid!' => \$uid,
			'ext_limit:i' => \$external_limit,
			'dir:s' => \$folder,
			'debug!' => \$debug,
             )  or die("\n Usage: ".$0." --user user --server server --password password [--port 993] [--nossl] [--uid] [--ext_limit 10] [--dir INBOX] \n\n\n"); 



chdir '/tmp/';

my @list_to_unsub;

$ssl = $ssl ? 1 : 0;
$uid = $uid ? 1 : 0;

if (not $password) {
 print "\n Type your password : ";
 $password = <>;
 chomp($password);
}

my $imap = Mail::IMAPClient->new( 
  Server => $server,
  User => $user,
  password => $password, 
  Port => $port, 
  Ssl=> $ssl,
  Uid=> $uid,

  ) or die "IMAP Failure: $@";

print "\n Connecting to server \n";

$imap->select($folder) or die "IMAP Select Error: $@";

 # How many msgs are we going to process
 print "There are ". $imap->unseen_count($folder).  " unseen messages of ". $imap->message_count($folder)." in the $folder folder.\n";

 # Store each message as an array element
 my @msgseqnos = $imap->unseen() or die "Couldn't get all unseen messages $@\n";
 my @msgs_to_delete;
 
 # Loop over the messages and store in file
 foreach my $seqno (@msgseqnos) {
	  my $parser = MIME::Parser->new;
	  my $entity = $parser->parse_data($imap->message_string($seqno));
	  my $header = $entity->head;
	  my $from = $header->get_all("From");
	  $from =~ s/\n//;  
	  $from =~ s/.*<(.*)>.*/$1/;
	  my $msg_id = $header->get("message-id");
	  my $subject = decode("MIME-Header", $header->get("subject"));
	  $subject=~ s/[^[:ascii:]]+/_/g;
	  $subject=~ s/\n//g;
	  print "From: ". $from . "  -> [". $subject ."] \n";
	  
	  my $know=0; 
	  foreach my $msg_in (@list_to_unsub) {
		  if ($from && ($msg_in->[2] eq $from)) {
			  $know=1; 
		  }	  
	  }
	  if (not $know ) {
	 
		  my $unsub = $header->get("List-Unsubscribe");
		  print  " List-Unsubscribe link : ";		   
		   
		  my $links;
		  $links = join(' ', $unsub) if ($unsub);

		  if ( ($unsub) and ($links =~ m/$RE{URI}{HTTP}{-keep}/)) {
			      $links = $1;
				  print  " Found !\n";
				  push(@list_to_unsub, [$seqno,$links,$from,$subject])
		  } else {
			 	  print  " No link! , Searching inside : " ;
				  my $gotlink = 0;
			      foreach my $split_entity ($entity) {
					  $gotlink = split_entity($split_entity,$from,$subject,$seqno);
					  last if ($gotlink);
				  }
				  print  " none " if (not $gotlink);
			      print  "\n"; 
		     } 
	  } else {
	  	  print "Sender $from, already know, skipping and deleting ...\n";
	      push(@msgs_to_delete,$seqno);  
	  }
 }
 
print "\n Unsubcribe :\n";

my @external_unsub;

foreach my $url (@list_to_unsub) {
    print "Trying to Self Unsubscribe : ";	 
    $ua->timeout(3);
    $ua->agent("Mozilla/5.0 (X11; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0");
    my $content = get($url->[1]);
    my $tree = HTML::Tree->new();
    $content = " " if (not $content);
    $tree->parse($content);
    my @links=$tree->findnodes(q{//a[@href]});
    my @inputs=$tree->findnodes(q{//input});
    print " got ". ($#links+1) ." links and ". ($#inputs+1). " inputs : ";
    if ($#links + $#inputs < -1 ) {
		print "Success ! \n";	
        push(@msgs_to_delete,$url->[0]);
	} else {
		if (($#external_unsub+1) < $external_limit) {
		    print "Failed Goto External \n";	
		    push(@external_unsub,[$url->[0],$url->[1]]); 
		} else {
		    print "Failed + External limit exceded ! Deleting \n";	
		    push(@msgs_to_delete,$url->[0]); 
		}		
	}
}

foreach my $url (@external_unsub) {
    print "Call external Unsubscribe : ";	 
	open_browser($url->[1]); 		
    push(@msgs_to_delete,$url->[0]);   
    print "OK\n";
}

print "Deleting ". ($#msgs_to_delete+1) . " messages  with ". ($#list_to_unsub + 1) ." Unsubscribe with " . ($#external_unsub + 1) . " external ...\n";	 
$imap->delete_message(\@msgs_to_delete); 

print "Closing server ...\n";	 
# Expunge and close the folder
$imap->expunge($folder);
$imap->close($folder);

# We're all done with IMAP here
$imap->logout();
print "Bye ...\n";	 


sub handle_other()
{
 my $handle = shift;
 my $path = $handle->path;
 print "\n Path : $path";
}

sub extract_links() {	
	 my $working_entity = shift;
	 my $from = shift;
	 $from =~ s/\n//;
	 
	 my $subject = shift;
	 $subject=~ s/\n//;

	 my $message_id = shift;
	 my $found =0;
	 FINISH: {
	 print Dumper($working_entity->effective_type) if $debug;
	 if (($working_entity->effective_type =~ /text\/plain/) || ($working_entity->effective_type =~ /text\/html/)) { # text message

		   my $tree=HTML::TreeBuilder::XPath->new_from_content($working_entity->bodyhandle->as_string);


		   # Easy link
  	       # we test "unsubscribe in url !

		   my $nodes=$tree->findnodes(q{//a[@href]});
		   while (my $node=$nodes->shift) {
		     for (@{  $node->extract_links('a')  }) {
		         my($link, $element, $attr, $tag) = @$_;
		         print "\n ** Debug ** : [$link] ** Debug **\n" if ($debug); 
		          if ($link =~ m/unsubscribe/) {	         
			         print  "Found ! \n";
			         push(@list_to_unsub, [$message_id,$link,$from,$subject]);
			         $found = 1;
			         last FINISH;
			     }  else {
		  	        print "."; 
			      }
		      }
		   }		     
		   
		   # Simple link
  	       # we test "unsubscribe" in the link anchor !

		   $nodes=$tree->findnodes(q{//a[@href]});
		   while (my $node=$nodes->shift) {
		     my @links = @{  $node->extract_links('a')  };  
		     if (&is_unsub_link(@links,$node, $message_id,$from,$subject)) {
			     $found = 1;
		         last FINISH;			  
			 }  else {
		  	    print "1"; 
			 }
		   }
		   # Long link
  	       # we test "unsubscribe" in the first parents link anchor !		   
		   $nodes=$tree->findnodes(q{//a[@href]/..});
		   while (my $node=$nodes->shift) {
		     my @links = @{  $node->extract_links('a')  };   
		     if (&is_unsub_link(@links,$node, $message_id,$from,$subject)) {
			     $found = 1;
		         last FINISH;			  
			 }  else {
		  	    print "2"; 
			 }
		  } 

		   # Triple links
  	       # we test "unsubscribe" in the first parents link anchor !		   
		   $nodes=$tree->findnodes(q{//a[@href]/../..});
		   while (my $node=$nodes->shift) {
		     my @links = @{  $node->extract_links('a')  };   
		     if (&is_unsub_link(@links,$node, $message_id,$from,$subject)) {
			     $found = 1;
		         last FINISH;			  
			 }  else {
		  	    print "3"; 
			 }
		  } 

      }
     }
   return $found;
}

sub is_unsub_link {
	my @links = shift;
	my $node = shift;
	my $message_id = shift;
	my $from = shift;
	my $subject= shift;
	my $found =0;
	#print "\n ** Debug ** : [". ref($node) ."] ** Debug **\n" if ($debug); 
	if ((ref($node) eq 'HTML::Element')) {
		my $trimed_txt = $node->as_trimmed_text;
		$trimed_txt=~ s/[^[:ascii:]]+/_/g;
		$trimed_txt=~ s/\n//g;
		$trimed_txt=~ s/\r//g;
        print "\n ** Debug ** : [" . $trimed_txt . "] ** Debug **\n" if ($debug); 
        #vous désinscrire
		#ne plus recevoir
		#Pour vous désabonner
	    if ($trimed_txt =~ m/sabonne|sinscri|spam|SPAM|\splus.*re.evoir|retir.*\sde\snos\s|retir.*\sdes\s|pouvez\sexercer\s.\stout\smoment|unsubscribe|cesser\sde\sre.evoir|cancel.*inscri|mais\sreceber/) {  
	         for (@{  $node->extract_links('a')  }) {
		         my($link, $element, $attr, $tag) = @$_;
		         print  "+";
		         push(@list_to_unsub, [$message_id,$link,$from,$subject]);
		         $found = 1;
		         print "\n ** Matched !!! ** Debug ** [$trimed_txt]\n" if ($debug); 
		         #last;
		      }
            print  " Found ! \n [$trimed_txt] \n" if ($found);
		 }
	     } # no unsubscribe link	     
	return $found;
}


############################################################
sub split_entity {
############################################################
  my $entity = shift; # needs a MIME::Entity object
  my $from = shift;
  my $subject= shift; 
  my $seqno = shift;
  my $gotlink;
  my $num_parts = $entity->parts; # how many mime parts?
   print "Nombre de Partie :  $num_parts\n" if $debug;
  if ($num_parts) { # we have a multipart mime message

    foreach (1..$num_parts) {
      split_entity( $entity->parts($_ - 1),$from ,$subject,$seqno);
    }

  } else { # we have a single mime message/part
	 $gotlink = &extract_links($entity,$from ,$subject,$seqno);
  }
  return $gotlink;
}




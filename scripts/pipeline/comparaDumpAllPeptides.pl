#!/usr/local/ensembl/bin/perl -w

use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Pipeline::Analysis;
use Bio::EnsEMBL::Pipeline::Rule;
use Bio::EnsEMBL::Compara::GenomeDB;
use Bio::EnsEMBL::DBLoader;


# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'compara_conf'} = {};
$self->{'compara_conf'}->{'-user'} = 'ensro';
$self->{'compara_conf'}->{'-port'} = 3306;

$self->{'speciesList'} = ();
$self->{'removeXedSeqs'} = undef;
$self->{'outputFasta'} = undef;
$self->{'noSplitSeqLines'} = undef;

my $conf_file;
my ($help, $host, $user, $pass, $dbname, $port, $adaptor);

GetOptions('help'     => \$help,
           'conf=s'   => \$conf_file,
           'dbhost=s' => \$host,
           'dbport=i' => \$port,
           'dbuser=s' => \$user,
           'dbpass=s' => \$pass,
           'dbname=s' => \$dbname,
           'fasta=s'  => \$self->{'outputFasta'},
           'noX=i'    => \$self->{'removeXedSeqs'},
           'nosplit'  => \$self->{'noSplitSeqLines'},
          );

if ($help) { usage(); }

parse_conf($self, $conf_file);

if($host)   { $self->{'compara_conf'}->{'-host'}   = $host; }
if($port)   { $self->{'compara_conf'}->{'-port'}   = $port; }
if($dbname) { $self->{'compara_conf'}->{'-dbname'} = $dbname; }
if($user)   { $self->{'compara_conf'}->{'-user'}   = $user; }
if($pass)   { $self->{'compara_conf'}->{'-pass'}   = $pass; }


unless(defined($self->{'compara_conf'}->{'-host'})
       and defined($self->{'compara_conf'}->{'-user'})
       and defined($self->{'compara_conf'}->{'-dbname'}))
{
  print "\nERROR : must specify host, user, and database to connect to compara\n\n";
  usage(); 
}

unless(defined($self->{'outputFasta'})) {
  print "\nERROR : must specify file into which to dump fasta sequences\n\n";
  usage();
}

$self->{'comparaDBA'}  = new Bio::EnsEMBL::Compara::DBSQL::DBAdaptor(%{$self->{'compara_conf'}});
$self->{'pipelineDBA'} = new Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor(-DBCONN => $self->{'comparaDBA'});

get_taxon_descriptions($self);  #creates hash from taxon_id to a description

dump_fasta($self);

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "comparaDumpAllPeptides.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -conf <path>           : config file describing compara, templates, and external genome databases\n";
  print "  -dbhost <machine>      : compara mysql database host <machine>\n";
  print "  -dbport <port#>        : compara mysql port number\n";
  print "  -dbname <name>         : compara mysql database <name>\n";
  print "  -dbuser <name>         : compara mysql connection user <name>\n";
  print "  -dbpass <pass>         : compara mysql connection password\n";
  print "  -fasta <path>          : file where fasta dump happens\n";
  print "  -noX <num>             : don't dump if <num> 'X's in a row in sequence\n";
  print "  -nosplit               : don't split sequence lines into readable format\n";
  print "comparaDumpAllPeptides.pl v1.1\n";
  
  exit(1);  
}


sub parse_conf {
  my $self      = shift;
  my $conf_file = shift;

  if($conf_file and (-e $conf_file)) {
    #read configuration file from disk
    my @conf_list = @{do $conf_file};

    foreach my $confPtr (@conf_list) {
      #print("HANDLE type " . $confPtr->{TYPE} . "\n");
      if($confPtr->{TYPE} eq 'COMPARA') {
        $self->{'compara_conf'} = $confPtr;
      }
      if($confPtr->{TYPE} eq 'BLAST_TEMPLATE') {
        $self->{'analysis_template'} = $confPtr;
      }
      if($confPtr->{TYPE} eq 'SPECIES') {
        push @{$self->{'speciesList'}}, $confPtr;
      }
    }
  }
}


sub dump_fasta {
  my $self = shift;

  my $sql = "SELECT member.stable_id, member.description, sequence.sequence, member.taxon_id " .
            " FROM member, sequence, source " .
            " WHERE member.source_id=source.source_id ".
            " AND source.source_name='ENSEMBLPEP' ".
            " AND member.sequence_id=sequence.sequence_id " .
            " GROUP BY member.member_id ORDER BY member.stable_id;";

  my $fastafile = $self->{'outputFasta'};
  my $descfile = $fastafile . ".desc";
  open FASTAFILE, ">$fastafile"
    or die "Could open $fastafile for output\n";
  open DESCFILE, ">$descfile"
    or die "Could open $descfile for output\n";
  print("writing fasta to loc '$fastafile'\n");

  my $sth = $self->{'comparaDBA'}->prepare( $sql );
  $sth->execute();

  my ($stable_id, $description, $sequence, $taxon_id);
  $sth->bind_columns( undef, \$stable_id, \$description, \$sequence, \$taxon_id );

  while( $sth->fetch() ) {
    #if removedXedSeqs defined then it contains the minimum num of
    # Xs in a row that is not acceptable, the regex X{#,}? says
    # if X occurs # or more times (not exhaustive search)
    unless($self->{'removeXedSeqs'} and ($sequence =~ /X{$self->{'removeXedSeqs'},}?/)) {
      $sequence =~ s/(.{72})/$1\n/g  unless($self->{'noSplitSeqLines'});
      print FASTAFILE ">$stable_id $description\n$sequence\n";
      print DESCFILE "ensemblpep\t$stable_id\t\t", $self->{'taxon_hash'}->{$taxon_id}, "\n";
    }
  }
  close(FASTAFILE);
  close(DESCFILE);

  $sth->finish();
}


sub get_taxon_descriptions {
  my $self = shift;

  $self->{'taxon_hash'} = {};
  
  my ($taxon_id, $genus, $species, $sub_species, $common_name, $classification);
  my $sql = "SELECT taxon_id, genus, species, sub_species, common_name, classification ".
            " FROM taxon";
  my $sth = $self->{'comparaDBA'}->prepare( $sql );
  $sth->execute();
  $sth->bind_columns(\$taxon_id, \$genus, \$species, \$sub_species, \$common_name, \$classification );
  while($sth->fetch()) {
    $classification =~ s/\s+/:/g;
    $sub_species='' if($sub_species eq 'NULL');
    my $taxonDesc = "taxon_id=$taxon_id;".
                    "taxon_genus=$genus;".
                    "taxon_species=$species;".
                    "taxon_sub_species=$sub_species;".
                    "taxon_common_name=$common_name;".
                    "taxon_classification=$classification;";
    $self->{'taxon_hash'}->{$taxon_id} = $taxonDesc;
    print("$taxonDesc\n");
  }
  $sth->finish;
}

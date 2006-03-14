#!/usr/local/ensembl/bin/perl -w

use strict;

my $description = q{
###########################################################################
##
## PROGRAM update_genome.pl
##
## AUTHORS
##    Javier Herrero (jherrero@ebi.ac.uk)
##
## COPYRIGHT
##    This script is part of the Ensembl project http://www.ensembl.org
##
## DESCRIPTION
##    This script takes the new core DB and a compara DB in production fase
##    and updates it in several steps:
##
##      - It updates the genome_db table
##      - It deletes all the genomic alignment data for the old genome_db
##      - It deletes all the syntenic data for the old genome_db
##      - It updates all the dnafrags for the given genome_db
##      - It cleans all the tables that are not related to genomic data
##
###########################################################################

};

=head1 NAME

update_genome.pl

=head1 AUTHORS

 Javier Herrero (jherrero@ebi.ac.uk)

=head1 COPYRIGHT

This script is part of the Ensembl project http://www.ensembl.org

=head1 DESCRIPTION

This script takes the new core DB and a compara DB in production phase and updates it in several steps:

 - It updates the genome_db table
 - It deletes all the genomic alignment data for the old genome_db
 - It deletes all the syntenic data for the old genome_db
 - It updates all the dnafrags for the given genome_db
 - It cleans all the tables that are not related to genomic data

=head1 SYNOPSIS

perl update_genome.pl --help

perl update_genome.pl
    [--reg_conf registry_configuration_file]
    --compara compara_db_name_or_alias
    --species new_species_db_name_or_alias
    [--[no]clean_database]
        This scripts can also truncate all the table that are not
        used in the genomic part of Compara. It is possible to avoid
        this by using the "--noclean_database" flag.
    [--[no]force]
        This scripts fails if the genome_db table of the compara DB
        already matches the new species DB. This options allows you
        to overcome this. USE ONLY IF YOU REALLY KNOW WHAT YOU ARE
        DOING!

=head1 OPTIONS

=head2 GETTING HELP

=over

=item B<[--help]>

  Prints help message and exits.

=back

=head2 GENERAL CONFIGURATION

=over

=item B<[--reg_conf registry_configuration_file]>

The Bio::EnsEMBL::Registry configuration file. If none given,
the one set in ENSEMBL_REGISTRY will be used if defined, if not
~/.ensembl_init will be used.

=back

=head2 DATABASES

=over

=item B<--compara compara_db_name_or_alias>

The compara database to update. You can use either the original name or any of the
aliases given in the registry_configuration_file

=item B<--species new_species_db_name_or_alias>

The core database of the species to update. You can use either the original name or
any of the aliases given in the registry_configuration_file

=back

=head2 OPTIONS

=over

=item B<[--[no]clean_database]>

This scripts can also truncate all the table that are not
used in the genomic part of Compara. It is possible to avoid
this by using the "--noclean_database" flag.

=item B<[--[no]force]>

This scripts fails if the genome_db table of the compara DB
already matches the new species DB. This options allows you
to overcome this. USE ONLY IF YOU REALLY KNOW WHAT YOU ARE
DOING!

=back

=head1 INTERNAL METHODS

=cut

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Utils::Exception qw(throw warning verbose);
use Getopt::Long;

my $usage = qq{
perl update_genome.pl
  
  Getting help:
    [--help]
  
  General configuration:
    [--reg_conf registry_configuration_file]
        the Bio::EnsEMBL::Registry configuration file. If none given,
        the one set in ENSEMBL_REGISTRY will be used if defined, if not
        ~/.ensembl_init will be used.
  Databases:
    --compara compara_db_name_or_alias
    --species new_species_db_name_or_alias

  Options:
    [--[no]clean_database]
        This scripts can also truncate all the table that are not
        used in the genomic part of Compara. It is possible to avoid
        this by using the "--noclean_database" flag.
    [--[no]force]
        This scripts fails if the genome_db table of the compara DB
        already matches the new species DB. This options allows you
        to overcome this. USE ONLY IF YOU REALLY KNOW WHAT YOU ARE
        DOING!
};

my $help;

my $reg_conf;
my $compara;
my $species;
my $force = 0;
my $clean_database = 1;

GetOptions(
    "help" => \$help,
    "reg_conf=s" => \$reg_conf,
    "compara=s" => \$compara,
    "species=s" => \$species,
    "force!" => \$force,
    "clean_database!" => \$clean_database,
  );

$| = 0;

# Print Help and exit if help is requested
if ($help) {
  print $description, $usage;
  exit(0);
}

##
## Configure the Bio::EnsEMBL::Registry
## Uses $reg_conf if supllied. Uses ENV{ENSMEBL_REGISTRY} instead if defined. Uses
## ~/.ensembl_init if all the previous fail.
##
Bio::EnsEMBL::Registry->load_all($reg_conf);

my $species_db = Bio::EnsEMBL::Registry->get_DBAdaptor($species, "core");
throw ("Cannot connect to database [$species]") if (!$species_db);

my $compara_db = Bio::EnsEMBL::Registry->get_DBAdaptor($compara, "compara");
throw ("Cannot connect to database [$compara]") if (!$compara_db);

my $genome_db = update_genome_db($species_db, $compara_db, $force);
print "Former " if (!$force);
print "Bio::EnsEMBL::Compara::GenomeDB->dbID: ", $genome_db->dbID, "\n\n";

delete_genomic_align_data($compara_db, $genome_db);

delete_syntenic_data($compara_db, $genome_db);

if (!$force) {
  update_dnafrags($compara_db, $genome_db, $species_db);
}

if ($clean_database) {
  print "Deleting non-genomic data from the database... ";
  foreach my $table ("member", "sequence", "analysis" ,"analysis_description", "peptide_align_feature",
      "homology", "homology_member", "family", "family_member", "domain", "domain_member") {
    $compara_db->dbc->do("TRUNCATE $table");
  }
  print "ok\n\n";
}

print_method_link_species_sets_to_update($compara_db, $genome_db);

exit(0);


=head2 update_genome_db

  Arg[1]      : Bio::EnsEMBL::DBSQL::DBAdaptor $species_dba
  Arg[2]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[3]      : bool $force
  Description : This method takes all the information needed from the
                species database in order to update the genome_db table
                of the compara database
  Returns     : The new Bio::EnsEMBL::Compara::GenomeDB object
  Exceptions  : throw if the genome_db table is up-to-date unless the
                --force option has been activated

=cut

sub update_genome_db {
  my ($species_dba, $compara_dba, $force) = @_;
  
  my $slice_adaptor = $species_dba->get_adaptor("Slice");
  my $primary_species_binomial_name = 
      $slice_adaptor->db->get_MetaContainer->get_Species->binomial;
  my ($highest_cs) = @{$slice_adaptor->db->get_CoordSystemAdaptor->fetch_all()};
  my $primary_species_assembly = $highest_cs->version();
  my $genome_db_adaptor = $compara_dba->get_GenomeDBAdaptor;
  my $genome_db = eval {$genome_db_adaptor->fetch_by_name_assembly(
          $primary_species_binomial_name,
          $primary_species_assembly
      )};
  if ($genome_db and $genome_db->dbID) {
    return $genome_db if ($force);
    throw "GenomeDB with this name [$primary_species_binomial_name] and assembly".
        " [$primary_species_assembly] is already in the compara DB [$compara]\n".
        "You can use the --force option IF YOU REALLY KNOW WHAT YOU ARE DOING!!";
  } elsif ($force) {
    print "GenomeDB with this name [$primary_species_binomial_name] and assembly".
        " [$primary_species_assembly] is not in the compara DB [$compara]\n".
        "You don't need the --force option!!";
    print "Press [Enter] to continue or Ctrl+C to cancel...";
    <STDIN>;
  }

  my $sql = "SELECT meta_value FROM meta where meta_key= ?";
  my $sth = $species_dba->dbc->prepare($sql);
  $sth->execute("assembly.default");
  my ($assembly) = $sth->fetchrow_array();
  if (!defined($assembly)) {
    warning "Cannot find assembly.default in meta table for $primary_species_binomial_name";
    $assembly = $primary_species_assembly;
  }
  $sth->execute("genebuild.version");
  my ($genebuild) = $sth->fetchrow_array();
  if (!defined($genebuild)) {
    warning "Cannot find genebuild.version in meta table for $primary_species_binomial_name";
    $genebuild = "";
  }
  print "New assembly and genebuild: ", join(" -- ", $assembly, $genebuild),"\n\n";

  $genome_db = eval{$genome_db_adaptor->fetch_by_name_assembly(
          $primary_species_binomial_name
      )};
  if ($genome_db) {
    $sql = "UPDATE genome_db SET assembly = \"$assembly\", genebuild = \"$genebuild\" WHERE genome_db_id = ".
        $genome_db->dbID;
    $sth = $compara_dba->dbc->do($sql); 
    $genome_db = $genome_db_adaptor->fetch_by_name_assembly(
            $primary_species_binomial_name,
            $primary_species_assembly
        );

  } else { ## New genome!!
    $sth->execute("species.taxonomy_id");
    my ($taxon_id) = $sth->fetchrow_array();
    if (!defined($taxon_id)) {
      throw "Cannot find species.taxonomy_id in meta table for $primary_species_binomial_name";
    }
    print "New genome in compara. Taxon #$taxon_id\n\n";
    $sql = "INSERT INTO genome_db (taxon_id, name, assembly, genebuild)".
        " VALUES (\"$taxon_id\", \"$primary_species_binomial_name\",".
        " \"$assembly\", \"$genebuild\")";
    $sth = $compara_dba->dbc->do($sql); 
    $genome_db = $genome_db_adaptor->fetch_by_name_assembly(
            $primary_species_binomial_name,
            $primary_species_assembly
        );
  }
  return $genome_db;
}

=head2 delete_genomic_align_data

  Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[2]      : Bio::EnsEMBL::Compara::GenomeDB $genome_db
  Description : This method deletes from the genomic_align,
                genomic_align_block and genomic_align_group tables
                all the rows that refer to the species identified
                by the $genome_db_id
  Returns     : -none-
  Exceptions  : throw if any SQL statment fails

=cut

sub delete_genomic_align_data {
  my ($compara_dba, $genome_db) = @_;

  print "Getting the list of genomic_align_block_id to remove... ";
  my $rows = $compara_dba->dbc->do(qq{
      CREATE TABLE list AS
          SELECT genomic_align_block_id
          FROM genomic_align_block, method_link_species_set
          WHERE genomic_align_block.method_link_species_set_id = method_link_species_set.method_link_species_set_id
          AND genome_db_id = $genome_db->{dbID}
    });
  throw $compara_dba->dbc->errstr if (!$rows);
  print "$rows elements found.\n";

  print "Deleting corresponding genomic_align, genomic_align_block and genomic_align_group rows...";
  $rows = $compara_dba->dbc->do(qq{
      DELETE
        genomic_align, genomic_align_block, genomic_align_group
      FROM
        list
        LEFT JOIN genomic_align_block USING (genomic_align_block_id)
        LEFT JOIN genomic_align USING (genomic_align_block_id)
        LEFT JOIN genomic_align_group USING (genomic_align_id)
      WHERE
        list.genomic_align_block_id = genomic_align.genomic_align_block_id
    });
  throw $compara_dba->dbc->errstr if (!$rows);
  print " ok!\n";

  print "Droping the list of genomic_align_block_ids...";
  $rows = $compara_dba->dbc->do(qq{DROP TABLE list});
  throw $compara_dba->dbc->errstr if (!$rows);
  print " ok!\n\n";
}

=head2 delete_syntenic_data

  Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[2]      : Bio::EnsEMBL::Compara::GenomeDB $genome_db
  Description : This method deletes from the dnafrag_region
                and synteny_region tables all the rows that refer
                to the species identified by the $genome_db_id
  Returns     : -none-
  Exceptions  : throw if any SQL statment fails

=cut

sub delete_syntenic_data {
  my ($compara_dba, $genome_db) = @_;

  print "Deleting dnafrag_region and synteny_region rows...";
  my $rows = $compara_dba->dbc->do(qq{
      DELETE
        dnafrag_region, synteny_region
      FROM
        dnafrag_region
        LEFT JOIN synteny_region USING (synteny_region_id)
        LEFT JOIN method_link_species_set USING (method_link_species_set_id)
      WHERE genome_db_id = $genome_db->{dbID}
    });
  throw $compara_dba->dbc->errstr if (!$rows);
  print " ok!\n\n";
}

=head2 update_dnafrags

  Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[2]      : Bio::EnsEMBL::Compara::GenomeDB $genome_db
  Arg[3]      : Bio::EnsEMBL::DBSQL::DBAdaptor $species_dba
  Description : This method fetches all the dnafrag in the compara DB
                corresponding to the $genome_db. It also gets the list
                of top_level seq_regions from the species core DB and
                updates the list of dnafrags in the compara DB.
  Returns     : -none-
  Exceptions  :

=cut

sub update_dnafrags {
  my ($compara_dba, $genome_db, $species_dba) = @_;

  my $dnafrag_adaptor = $compara_dba->get_adaptor("DnaFrag");
  my $old_dnafrags = $dnafrag_adaptor->fetch_all_by_GenomeDB_region($genome_db);
  my $old_dnafrags_by_id;
  foreach my $old_dnafrag (@$old_dnafrags) {
    $old_dnafrags_by_id->{$old_dnafrag->dbID} = $old_dnafrag;
  }

  my $sql1 = qq{
      SELECT
        cs.name,
        sr.name,
        sr.length
      FROM
        coord_system cs,
        seq_region sr,
        seq_region_attrib sra,
        attrib_type at
      WHERE
        sra.attrib_type_id = at.attrib_type_id
        AND at.code = 'toplevel'
        AND sr.seq_region_id = sra.seq_region_id
        AND sr.coord_system_id = cs.coord_system_id
    };
  my $sth1 = $species_dba->dbc->prepare($sql1);
  $sth1->execute();
  my $current_verbose = verbose();
  verbose('EXCEPTION');
  while (my ($coordinate_system_name, $name, $length) = $sth1->fetchrow_array) {
    my $new_dnafrag = new Bio::EnsEMBL::Compara::DnaFrag(
            -genome_db => $genome_db,
            -coord_system_name => $coordinate_system_name,
            -name => $name,
            -length => $length
        );
    my $dnafrag_id = $dnafrag_adaptor->update($new_dnafrag);
    delete($old_dnafrags_by_id->{$dnafrag_id});
    throw() if ($old_dnafrags_by_id->{$dnafrag_id});
  }
  verbose($current_verbose);
  print "Deleting ", scalar(keys %$old_dnafrags_by_id), " former DnaFrags...";
  foreach my $deprecated_dnafrag_id (keys %$old_dnafrags_by_id) {
    $compara_dba->dbc->do("DELETE FROM dnafrag WHERE dnafrag_id = ".$deprecated_dnafrag_id) ;
  }
  print "  ok!\n\n";
}

=head2 print_method_link_species_sets_to_update

  Arg[1]      : Bio::EnsEMBL::Compara::DBSQL::DBAdaptor $compara_dba
  Arg[2]      : Bio::EnsEMBL::Compara::GenomeDB $genome_db
  Description : This method prints all the genomic MethodLinkSpeciesSet
                that need to be updated (those which correspond to the
                $genome_db).
                NB: Only method_link with a dbID <200 are taken into
                account (they should be the genomic ones)
  Returns     : -none-
  Exceptions  :

=cut

sub print_method_link_species_sets_to_update {
  my ($compara_dba, $genome_db) = @_;

  my $method_link_species_set_adaptor = $compara_dba->get_adaptor("MethodLinkSpeciesSet");
  my $method_link_species_sets = $method_link_species_set_adaptor->fetch_all_by_GenomeDB($genome_db);

  print "List of Bio::EnsEMBL::Compara::MethodLinkSpeciesSet to update:\n";
  foreach my $this_method_link_species_set (sort {$a->method_link_id <=> $b->method_link_id} @$method_link_species_sets) {
    last if ($this_method_link_species_set->method_link_id > 200); # Avoid non-genomic method_link_species_set
    printf "%8d: ", $this_method_link_species_set->dbID,;
    print $this_method_link_species_set->method_link_type, " (",
        join(",", map {$_->name} @{$this_method_link_species_set->species_set}), ")\n";
  }

}

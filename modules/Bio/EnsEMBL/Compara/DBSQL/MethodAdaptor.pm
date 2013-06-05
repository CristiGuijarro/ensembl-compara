=head1 LICENSE

  Copyright (c) 1999-2013 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.

=cut

=head1 NAME

Bio::EnsEMBL::Compara::DBSQL::MethodAdaptor

=head1 SYNOPSIS

    my $method_adaptor  = $db_adaptor->get_MethodAdaptor();

    my $all_methods     = $method_adaptor->fetch_all();             # inherited method

    my $method_by_id    = $method_adaptor->fetch_by_dbID( 301 );    # inherited method

    my $bzn_method      = $method_adaptor->fetch_by_type('BLASTZ_NET');
    my $fam_method      = $method_adaptor->fetch_by_type('FAMILY');

    foreach my $tree_method (@{ $method_adaptor->fetch_by_class_pattern('%tree_node')}) {
        print $tree_method->toString."\n";
    }

    $method_adaptor->store( $my_method );

=head1 DESCRIPTION

Database adaptor to store and fetch Method objects

=head1 METHODS

=cut


package Bio::EnsEMBL::Compara::DBSQL::MethodAdaptor;

use strict;

use Bio::EnsEMBL::Compara::Method;
use base ('Bio::EnsEMBL::Compara::DBSQL::BaseFullCacheAdaptor');


sub object_class {
    return 'Bio::EnsEMBL::Compara::Method';
}


sub _tables {

    return (['method_link','m'])
}


sub _columns {

        #warning _objs_from_sth implementation depends on ordering
    return qw (
        m.method_link_id
        m.type
        m.class
    );
}

sub _unique_attributes {
    return qw(
        type
    );
}


sub _objs_from_sth {
    my ($self, $sth) = @_;

    my @methods = ();

    while ( my ($dbID, $type, $class) = $sth->fetchrow() ) {
        push @methods, Bio::EnsEMBL::Compara::Method->new(
            -dbID => $dbID,
            -type => $type,
            -class => $class,
            -adaptor => $self,
        );
    }

    return \@methods;
}


=head2 fetch_by_type

  Arg [1]     : string $type
  Example     : my $bzn_method = $method_adaptor->fetch_by_type('BLASTZ_NET');
  Description : Fetches the Method object(s) with a given type
  Returntype  : Bio::EnsEMBL::Compara::Method

=cut

sub fetch_by_type {
    my ($self, $type) = @_;

    foreach my $method (@{$self->fetch_all}) {
        return $method if $method->type eq $type;
    }
    return undef;
}


=head2 fetch_all_by_class_pattern

  Arg [1]     : string $class_pattern
  Example     : my @tree_methods = @{ $method_adaptor->fetch_by_class_pattern('.*tree_node') };
  Description : Fetches the Method object(s) with a class matching the given pattern
  Returntype  : Bio::EnsEMBL::Compara::Method arrayref

=cut

# TODO used ??

sub fetch_all_by_class_pattern {
    my ($self, $class_pattern) = @_;

    my @matched_methods;
    foreach my $method (@{$self->fetch_all}) {
        push @matched_methods, $method if $method->class =~ m/$class_pattern/;
    }
    return \@matched_methods
}


=head2 store

  Arg [1]     : Bio::EnsEMBL::Compara::Method $method
  Example     : $method_adaptor->store( $my_method );
  Description : Stores the Method object in the database unless it has been stored already; updates the dbID of the object.
  Returntype  : Bio::EnsEMBL::Compara::Method

=cut

sub store {
    my ($self, $method) = @_;

    if(my $reference_dba = $self->db->reference_dba()) {
        $reference_dba->get_MethodAdaptor->store( $method );
    }

    unless($self->_synchronise($method)) {
        my $sql = 'INSERT INTO method_link (method_link_id, type, class) VALUES (?, ?, ?)';
        my $sth = $self->prepare( $sql ) or die "Could not prepare $sql";

        my $return_code = $sth->execute( $method->dbID(), $method->type(), $method->class() )
                # using $return_code in boolean context allows to skip the value '0E0' ('no rows affected') that Perl treats as zero but regards as true:
            or die "Could not store ".$method->toString;

        if($return_code > 0) {     # <--- for the same reason we have to be explicitly numeric here
            $self->attach($method, $self->dbc->db_handle->last_insert_id(undef, undef, 'method_link', 'method_link_id') );
            $sth->finish();
        }
    }
    return $method;
}


1;

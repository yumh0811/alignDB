#!/usr/bin/perl
use strict;
use warnings;

use Template;
use File::Basename;
use File::Find::Rule;
use File::Remove qw(remove);
use File::Spec;
use String::Compare;
use YAML qw(Dump Load DumpFile LoadFile);

my $store_dir = shift
    || File::Spec->catdir( $ENV{HOME}, "data/alignment/aspergillus" );
my $parallel = 12;

{    # on linux
    my $data_dir
        = File::Spec->catdir( $ENV{HOME}, "data/alignment/aspergillus" );
    my $pl_dir      = File::Spec->catdir( $ENV{HOME}, "Scripts" );
    my $kentbin_dir = File::Spec->catdir( $ENV{HOME}, "bin/x86_64" );

    # ensembl genomes 65
    my $fasta_dir = File::Spec->catdir( $ENV{HOME},
        "data/ensemblgenomes12_65/fungi/fasta" );
    my $mysql_dir = File::Spec->catdir( $ENV{HOME},
        "data/ensemblgenomes12_65/fungi/mysql" );

    my $tt = Template->new;

    my @data = (
        {   taxon    => 5057,
            name     => "Acla",
            sciname  => "Aspergillus clavatus",
            coverage => "11.4x sanger",
        },
        {   taxon    => 5059,
            name     => "Afla",
            sciname  => "Aspergillus flavus",
            coverage => "5x sanger",
        },
        {   taxon     => 330879,
            name      => "Afum",
            sciname   => "Aspergillus fumigatus",
            othername => "Aspergillus fumigatus Af293",
            coverage  => "10.5x sanger",
        },
        {   taxon     => 162425,
            name      => "Anid",
            sciname   => "Aspergillus nidulans",
            othername => "Emericella nidulans",
            coverage  => "13x sanger",
        },
        {   taxon    => 5061,
            name     => "Anig",
            sciname  => "Aspergillus niger",
            coverage => "7.5x sanger",
        },
        {   taxon     => 5062,
            name      => "Aory",
            sciname   => "Aspergillus oryzae",
            othername => "Eurotium nidulans",
            coverage  => "9x sanger",
        },
        {   taxon    => 33178,
            name     => "Ater",
            sciname  => "Aspergillus terreus",
            coverage => "11.05x sanger",
        },
        {   taxon     => 36630,
            name      => "Nfis",
            sciname   => "Neosartorya fischeri",
            othername => "Aspergillus fischeri",
            coverage  => "11.0x sanger",
        },
    );

    my @subdirs_fasta = File::Find::Rule->directory->in($fasta_dir);
    my @subdirs_mysql = File::Find::Rule->directory->in($mysql_dir);

    for my $item (@data) {
        my $folder = $item->{sciname};
        $folder =~ s/ /_/g;
        $folder = lc $folder;

        #$folder .= "/dna";

        # match the most similar name
        my ($fasta) = map { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
            map { [ $_, compare( lc basename($_), $folder . "/dna" ) ] }
            @subdirs_fasta;
        $item->{fasta} = $fasta;

        my ($mysql) = map { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
            map { [ $_, compare( lc basename($_), $folder . "_core" ) ] }
            @subdirs_mysql;
        $item->{mysql} = $mysql;

        $item->{db} = lc $item->{name} . "_65";

        # prepare working dir
        my $dir = File::Spec->catdir( $data_dir, $item->{name} );
        mkdir $dir if !-e $dir;
        $item->{dir} = $dir;
    }

    # taxon.csv
    my $text = <<'EOF';
[% FOREACH item IN data -%]
[% item.taxon %],[% item.sciname FILTER replace(' ', ',') %],[% item.name %],,
[% END -%]
EOF
    $tt->process(
        \$text,
        { data => \@data, },
        File::Spec->catfile( $store_dir, "taxon.csv" )
    ) or die Template->error;

    # chr_length.csv
    $text = <<'EOF';
[% FOREACH item IN data -%]
[% item.taxon %],chrUn,999999999,[% item.name %]/ensemblgenomes65
[% END -%]
EOF
    $tt->process(
        \$text,
        { data => \@data, },
        File::Spec->catfile( $store_dir, "chr_length.csv" )
    ) or die Template->error;

    $text = <<'EOF';
#!/bin/bash
cd [% data_dir %]

#----------------------------#
# unzip, filter and split
#----------------------------#
[% FOREACH item IN data -%]
# [% item.name %] [% item.coverage %] 
echo [% item.name %]

cd [% item.dir %]
find [% item.fasta %] -name "*dna.toplevel*" | xargs gzip -d -c > toplevel.fa
[% kentbin_dir %]/faCount toplevel.fa | perl -aln -e 'next if $F[0] eq 'total'; print $F[0] if $F[1] > 100000; print $F[0] if $F[1] > 10000  and $F[6]/$F[1] < 0.05' | uniq > listFile
[% kentbin_dir %]/faSomeRecords toplevel.fa listFile toplevel.filtered.fa
[% kentbin_dir %]/faSplit byname toplevel.filtered.fa .
rm toplevel.fa toplevel.filtered.fa listFile

[% IF item.name != 'Afum' and item.name != 'Aory' -%]
rename 's/fa$/fasta/' *.fa
[% END -%]

[% END -%]

EOF

    $tt->process(
        \$text,
        {   data        => \@data,
            data_dir    => $data_dir,
            pl_dir      => $pl_dir,
            kentbin_dir => $kentbin_dir
        },
        File::Spec->catfile( $store_dir, "file.sh" )
    ) or die Template->error;

    $text = <<'EOF';
#!/bin/bash
cd [% data_dir %]

#----------------------------#
# Ensembl annotation or RepeatMasker
#----------------------------#
[% FOREACH item IN data -%]
[% IF item.name == 'Afum' or item.name == 'Aory' -%]
# [% item.name %] [% item.coverage %]
echo [% item.name %]

cd [% item.dir %]

if [ ! -f [% item.db %]_repeat.yml ]; then perl [% pl_dir %]/alignDB/util/build_ensembl.pl --initdb --db [% item.db %] --ensembl [% item.mysql %];  fi;
if [ ! -f [% item.db %]_repeat.yml ]; then perl [% pl_dir %]/alignDB/util/write_masked_chr.pl -e [% item.db %]; fi;
perl [% pl_dir %]/alignDB/util/write_masked_chr.pl -y [% item.db %]_repeat.yml --dir [% item.dir %]

find . -name "*fa" | xargs rm
rename 's/\.masked//' *.fa.masked
rename 's/^/chr/' *.fa

if [ -f chrUn.fasta ];
then
    [% kentbin_dir %]/faSplit about [% item.dir %]/chrUn.fasta 100000000 [% item.dir %]/;
    rm [% item.dir %]/chrUn.fasta;    
    rename 's/fa$/fasta/' [0-9][0-9].fa;
fi;

RepeatMasker [% item.dir %]/*.fasta -species Fungi -xsmall --parallel [% parallel %]
if [ -f *.fasta.masked ];
then
    rename 's/fasta.masked$/fa/' *.fasta.masked;
fi;
find [% item.dir %] -type f -name "*fasta*" | xargs rm 

[% ELSE %]
# [% item.name %] [% item.coverage %]
echo [% item.name %]

cd [% item.dir %]
RepeatMasker [% item.dir %]/*.fasta -species Fungi -xsmall --parallel [% parallel %]
rename 's/fasta.masked$/fa/' *.fasta.masked
find [% item.dir %]  -type f -name "*fasta*" | xargs rm

[% END -%]
[% END -%]

EOF

    $tt->process(
        \$text,
        {   data        => \@data,
            data_dir    => $data_dir,
            pl_dir      => $pl_dir,
            kentbin_dir => $kentbin_dir,
            parallel    => $parallel,
        },
        File::Spec->catfile( $store_dir, "ensemblrm.sh" )
    ) or die Template->error;

    $text = <<'EOF';
#!/bin/bash
cd [% data_dir %]

#----------------------------#
# blastz Afum
#----------------------------#
[% FOREACH item IN data -%]
[% IF item.name != 'Afum' -%]
# [% item.name %] [% item.coverage %]
perl [% pl_dir %]/blastz/bz.pl \
    -dt [% data_dir %]/Afum -dq [% data_dir %]/[% item.name %] \
    -dl [% data_dir %]/Afumvs[% item.name %] \
    -s set01 -p [% parallel %] --noaxt -pb lastz --lastz

[% END -%]
[% END -%]

#----------------------------#
# blastz Aory
#----------------------------#
[% FOREACH item IN data -%]
[% IF item.name != 'Aory' -%]
# [% item.name %] [% item.coverage %]
perl [% pl_dir %]/blastz/bz.pl \
    -dt [% data_dir %]/Aory -dq [% data_dir %]/[% item.name %] \
    -dl [% data_dir %]/Aoryvs[% item.name %] \
    -s set01 -p [% parallel %] --noaxt -pb lastz --lastz

[% END -%]
[% END -%]

EOF
    $tt->process(
        \$text,
        {   data        => \@data,
            data_dir    => $data_dir,
            pl_dir      => $pl_dir,
            kentbin_dir => $kentbin_dir,
            parallel    => $parallel,
        },
        File::Spec->catfile( $store_dir, "bz.sh" )
    ) or die Template->error;

    $text = <<'EOF';
#!/bin/bash
cd [% data_dir %]

#----------------------------#
# lpcna Afum
#----------------------------#
[% FOREACH item IN data -%]
[% IF item.name != 'Afum' -%]
# [% item.name %] [% item.coverage %]
perl [% pl_dir %]/blastz/lpcna.pl \
    -dt [% data_dir %]/Afum -dq [% data_dir %]/[% item.name %] \
    -dl [% data_dir %]/Afumvs[% item.name %] -p [% parallel %]

[% END -%]
[% END -%]

#----------------------------#
# lpcna Aory
#----------------------------#
[% FOREACH item IN data -%]
[% IF item.name != 'Aory' -%]
# [% item.name %] [% item.coverage %]
perl [% pl_dir %]/blastz/lpcna.pl \
    -dt [% data_dir %]/Aory -dq [% data_dir %]/[% item.name %] \
    -dl [% data_dir %]/Aoryvs[% item.name %] -p [% parallel %]

[% END -%]
[% END -%]

EOF
    $tt->process(
        \$text,
        {   data        => \@data,
            data_dir    => $data_dir,
            pl_dir      => $pl_dir,
            kentbin_dir => $kentbin_dir,
            parallel    => $parallel,
        },
        File::Spec->catfile( $store_dir, "lpcna.sh" )
    ) or die Template->error;

    $text = <<'EOF';
#!/bin/bash
    
#----------------------------#
# amp Afum
#----------------------------#
[% FOREACH item IN data -%]
[% IF item.name != 'Afum' -%]
# [% item.name %] [% item.coverage %]
perl [% pl_dir %]/blastz/amp.pl -syn \
    -dt [% data_dir %]/Afum -dq [% data_dir %]/[% item.name %] \
    -dl [% data_dir %]/Afumvs[% item.name %] -p [% parallel %]

[% END -%]
[% END -%]
    
#----------------------------#
# amp
#----------------------------#
[% FOREACH item IN data -%]
[% IF item.name != 'Aory' -%]
# [% item.name %] [% item.coverage %]
perl [% pl_dir %]/blastz/amp.pl -syn \
    -dt [% data_dir %]/Aory -dq [% data_dir %]/[% item.name %] \
    -dl [% data_dir %]/Aoryvs[% item.name %] -p [% parallel %]

[% END -%]
[% END -%]

EOF
    $tt->process(
        \$text,
        {   data        => \@data,
            data_dir    => $data_dir,
            pl_dir      => $pl_dir,
            kentbin_dir => $kentbin_dir,
            parallel    => $parallel,
        },
        File::Spec->catfile( $store_dir, "amp.sh" )
    ) or die Template->error;

    $text = <<'EOF';
#!/bin/bash
cd [% data_dir %]

#----------------------------#
# stat
#----------------------------#
[% FOREACH item IN data -%]
[% IF item.name != 'Afum' -%]
# [% item.name %]
perl [% pl_dir %]/alignDB/extra/two_way_batch.pl \
    -d Afumvs[% item.name %] \
    -t="330879,Afum" -q "[% item.taxon %],[% item.name %]" \
    -a [% data_dir %]/Afumvs[% item.name %] \
    -at 5000 -st 0 -ct 0 --parallel [% parallel %] --run 1-3,21,40

[% END -%]
[% END -%]

[% FOREACH item IN data -%]
[% IF item.name != 'Aory' -%]
# [% item.name %]
perl [% pl_dir %]/alignDB/extra/two_way_batch.pl \
    -d Aoryvs[% item.name %] \
    -t="5062,Aory" -q "[% item.taxon %],[% item.name %]" \
    -a [% data_dir %]/Aoryvs[% item.name %] \
    -at 5000 -st 0 -ct 0 --parallel [% parallel %] --run 1-3,21,40

[% END -%]
[% END -%]


EOF
    $tt->process(
        \$text,
        {   data     => \@data,
            data_dir => $data_dir,
            pl_dir   => $pl_dir,
            parallel => $parallel,
        },
        File::Spec->catfile( $store_dir, "pair_stat.sh" )
    ) or die Template->error;

    $text = <<'EOF';
#!/bin/bash

#----------------------------#
# clean RepeatMasker outputs
#----------------------------#
# find [% data_dir %] -name "*.fasta*" | xargs rm

#----------------------------#
# only keeps chr.2bit files
#----------------------------#
# find [% data_dir %] -name "*.fa" | xargs rm

#----------------------------#
# clean pairwise maf
#----------------------------#
# find [% data_dir %] -name "mafSynNet" | xargs rm -fr
# find [% data_dir %] -name "mafNet" | xargs rm -fr

#----------------------------#
# gzip maf, fas
#----------------------------#
find [% data_dir %] -name "*.maf" | parallel gzip
find [% data_dir %] -name "*.maf.fas" | parallel gzip

#----------------------------#
# clean maf-fasta
#----------------------------#
# rm -fr [% data_dir %]/*_fasta

EOF
    $tt->process(
        \$text,
        {   data        => \@data,
            data_dir    => $data_dir,
            pl_dir      => $pl_dir,
            kentbin_dir => $kentbin_dir,
        },
        File::Spec->catfile( $store_dir, "clean.sh" )
    ) or die Template->error;
}

{    # multiz
    my $data_dir
        = File::Spec->catdir( $ENV{HOME}, "data/alignment/aspergillus" );
    my $pl_dir = File::Spec->catdir( $ENV{HOME}, "Scripts" );

    my $tt = Template->new;
    my $strains_of
        = { AfumvsVII => [qw{ Acla Afla Anid Anig Aory Ater Nfis }], };

    my @data;
    for my $key ( sort keys %{$strains_of} ) {
        my @strains = @{ $strains_of->{$key} };
        push @data,
            {
            out_dir => $key,
            strains => \@strains,
            };
    }

    my $text = <<'EOF';
#!/bin/bash
    
#----------------------------#
# mz
#----------------------------#
# find . -name "*MT.synNet*" | xargs rm

[% FOREACH item IN data -%]
# [% item.out_dir %]
perl [% pl_dir %]/blastz/mz.pl \
    [% FOREACH st IN item.strains -%]
    -d [% data_dir %]/Afumvs[% st %] \
    [% END -%]
    --tree [% data_dir %]/8way.nwk \
    --out [% data_dir %]/[% item.out_dir %] \
    -syn -p [% parallel %]

[% END -%]

EOF
    $tt->process(
        \$text,
        {   data     => \@data,
            data_dir => $data_dir,
            pl_dir   => $pl_dir,
            parallel => $parallel,
        },
        File::Spec->catfile( $store_dir, "mz.sh" )
    ) or die Template->error;

    $text = <<'EOF';
#----------------------------#
# maf2fasta
#----------------------------#
[% FOREACH item IN data -%]
# [% item.out_dir %]
perl [% pl_dir %]/blastz/maf2fasta.pl \
    --has_outgroup --id 330879 -p [% parallel %] --block \
    -i [% data_dir %]/[% item.out_dir %] \
    -o [% data_dir %]/[% item.out_dir %]_fasta

[% END -%]

#----------------------------#
# mafft
#----------------------------#
[% FOREACH item IN data -%]
# [% item.out_dir %]
perl [% pl_dir %]/blastz/refine_fasta.pl \
    --msa mafft --block -p [% parallel %] \
    -i [% data_dir %]/[% item.out_dir %]_fasta \
    -o [% data_dir %]/[% item.out_dir %]_mft

[% END -%]

#----------------------------#
# muscle-quick
#----------------------------#
#[% FOREACH item IN data -%]
## [% item.out_dir %]
#perl [% pl_dir %]/blastz/refine_fasta.pl \
#    --msa muscle --quick --block -p [% parallel %] \
#    -i [% data_dir %]/[% item.out_dir %]_fasta \
#    -o [% data_dir %]/[% item.out_dir %]_mslq
#
#[% END -%]

EOF

    $tt->process(
        \$text,
        {   data     => \@data,
            data_dir => $data_dir,
            pl_dir   => $pl_dir,
            parallel => $parallel,
        },
        File::Spec->catfile( $store_dir, "maf_fasta.sh" )
    ) or die Template->error;

    $text = <<'EOF';
#!/bin/bash
    
#----------------------------#
# multi_way_batch
#----------------------------#
[% FOREACH item IN data -%]
# [% item.out_dir %]
# mafft
perl [% pl_dir %]/alignDB/extra/multi_way_batch.pl \
    -d [% item.out_dir %] -e Afum_65 \
    --block --id 330879 \
    -f [% data_dir %]/[% item.out_dir %]_mft  \
    -lt 5000 -st 0 -ct 0 --parallel [% parallel %] --run 1-3,21,40

[% END -%]

EOF
    $tt->process(
        \$text,
        {   data     => \@data,
            data_dir => $data_dir,
            pl_dir   => $pl_dir,
            parallel => $parallel,
        },
        File::Spec->catfile( $store_dir, "multi.sh" )
    ) or die Template->error;
}

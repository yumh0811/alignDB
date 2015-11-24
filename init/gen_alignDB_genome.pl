#!/usr/bin/perl
use strict;
use warnings;
use autodie;

use Getopt::Long qw(HelpMessage);
use Config::Tiny;
use FindBin;
use YAML qw(Dump Load DumpFile LoadFile);

use File::Find::Rule;

use AlignDB::IntSpan;
use AlignDB::Run;
use AlignDB::Stopwatch;
use AlignDB::Util qw(:all);

use lib "$FindBin::Bin/../lib";
use AlignDB;

#----------------------------------------------------------#
# GetOpt section
#----------------------------------------------------------#
my $Config = Config::Tiny->read("$FindBin::Bin/../alignDB.ini");

# record ARGV and Config
my $stopwatch = AlignDB::Stopwatch->new(
    program_name => $0,
    program_argv => [@ARGV],
    program_conf => $Config,
);

=head1 NAME

gen_alignDB_genome.pl - Generate alignDB from genome fasta files

=head1 SYNOPSIS

    perl gen_alignDB_genome.pl [options]
      Options:
        --help      -?          brief help message
        --server    -s  STR     MySQL server IP/Domain name
        --port      -P  INT     MySQL server port
        --db        -d  STR     database name
        --username  -u  STR     username
        --password  -p  STR     password
        --dir_align -da STR     fasta files' directory
        --target        STR     "target_taxon_id,target_name"
        --length        INT     truncated length
        --fill          INT     fill holes less than this
        --min           INT     minimal length
        --parallel      INT     run in parallel mode

    perl init/init_alignDB.pl -d Athvsself
    perl init/gen_alignDB_genome.pl -d Athvsself -t "3702,Ath" --dir /home/wangq/data/alignment/arabidopsis19/ath_65  --parallel 4
    
    >perl init_alignDB.pl -d nipvsself
    >perl gen_alignDB_genome.pl -d nipvsself -t "39947,Nip" --dir e:\data\alignment\rice\nip_58\  --parallel 4
    
    >perl init_alignDB.pl -d 9311vsself
    >perl gen_alignDB_genome.pl -d 9311vsself -t "39946,9311" --dir e:\data\alignment\rice\9311_58\  --parallel 4
    
    perl init/init_alignDB.pl -d S288Cvsself
    perl init/gen_alignDB_genome.pl -d S288Cvsself -t "4932,S288C" --dir /home/wangq/data/alignment/yeast65/S288C/  --parallel 4
    perl init/insert_gc.pl -d S288Cvsself --parallel 4

=cut

GetOptions(
    'help|?' => sub { HelpMessage(0) },
    'server|s=s'   => \( my $server   = $Config->{database}{server} ),
    'port|P=i'     => \( my $port     = $Config->{database}{port} ),
    'db|d=s'       => \( my $db       = $Config->{database}{db} ),
    'username|u=s' => \( my $username = $Config->{database}{username} ),
    'password|p=s' => \( my $password = $Config->{database}{password} ),
    'dir_align|dir|da=s' => \( my $dir ),
    'target=s'           => \( my $target ),
    'length=i'           => \( my $truncated_length = 100_000 ),
    'fill=i'             => \( my $fill = 50 ),
    'min=i'              => \( my $min_length = 5000 ),
    'parallel=i'         => \( my $parallel = $Config->{generate}{parallel} ),
) or HelpMessage(1);

#----------------------------------------------------------#
# Search for all files and push their paths to @axt_files
#----------------------------------------------------------#
my @files = sort File::Find::Rule->file->name( '*.fa', '*.fas', '*.fasta' )->in($dir);
printf "\n----Total .fa Files: %4s----\n\n", scalar @files;

{    # update names
    my $obj = AlignDB->new(
        mysql  => "$db:$server",
        user   => $username,
        passwd => $password,
    );

    # Database handler
    my $dbh = $obj->dbh;

    my ( $target_taxon_id, $target_name ) = split ",", $target;
    $target_name = $target_taxon_id unless $target_name;

    $obj->update_names( { $target_taxon_id => $target_name } );
}

#----------------------------------------------------------#
# worker
#----------------------------------------------------------#
my $worker = sub {
    my $infile = shift;

    my $inner_watch = AlignDB::Stopwatch->new;
    $inner_watch->block_message("Process $infile...");

    my $obj = AlignDB->new(
        mysql  => "$db:$server",
        user   => $username,
        passwd => $password,
    );

    my ( $target_taxon_id, $target_name ) = split ",", $target;

    die "target_taxon_id not defined\n" unless $target_taxon_id;
    $target_name = $target_taxon_id unless $target_name;

    my $chr_name = path($infile)->basename->stringify;
    $chr_name =~ s/\..+?$//;

    my ( $seq_of, $seq_names ) = read_fasta($infile);
    my $chr_seq    = $seq_of->{ $seq_names->[0] };
    my $chr_length = length $chr_seq;

    my $id_hash = $obj->get_chr_id_hash($target_taxon_id);
    my $chr_id  = $id_hash->{$chr_name};
    return unless $chr_id;

    my $ambiguous_set = AlignDB::IntSpan->new;
    for ( my $pos = 0; $pos < $chr_length; $pos++ ) {
        my $base = substr $chr_seq, $pos, 1;
        if ( $base =~ /[^ACGT-]/i ) {
            $ambiguous_set->add( $pos + 1 );
        }
    }

    print "Ambiguous chromosome region for $chr_name:\n    " . $ambiguous_set->runlist . "\n";

    my $valid_set = AlignDB::IntSpan->new("1-$chr_length");
    $valid_set->subtract($ambiguous_set);
    $valid_set = $valid_set->fill( $fill - 1 );    # fill gaps smaller than $fill

    print "Valid chromosome region for $chr_name:\n    " . $valid_set->runlist . "\n";

    my @regions;                                   # ([start, end], [start, end], ...)
    for my $set ( $valid_set->sets ) {
        my $size = $set->size;
        next if $size < $min_length;

        my @set_regions;
        my $pos = $set->min;
        my $max = $set->max;
        while ( $max - $pos + 1 > $truncated_length ) {
            push @set_regions, [ $pos, $pos + $truncated_length - 1 ];
            $pos += $truncated_length;
        }
        if ( scalar @set_regions > 0 ) {
            $set_regions[-1]->[1] = $max;
        }
        else {
            @set_regions = ( [ $pos, $max ] );
        }
        push @regions, @set_regions;
    }

    #print Dump \@regions;

    for my $region (@regions) {
        my ( $start, $end ) = @{$region};
        my $seq = substr $chr_seq, $start - 1, $end - $start + 1;

        my $info_refs = [
            {   taxon_id   => $target_taxon_id,
                name       => $target_name,
                chr_id     => $chr_id,
                chr_name   => $chr_name,
                chr_start  => $start,
                chr_end    => $end,
                chr_strand => '+',
                seq        => $seq,
            },
            {   taxon_id   => $target_taxon_id,
                name       => $target_name,
                chr_id     => $chr_id,
                chr_name   => $chr_name,
                chr_start  => $start,
                chr_end    => $end,
                chr_strand => '+',
                seq        => $seq,
            },
        ];

        $obj->add_align( $info_refs, [ $seq, $seq ], );
    }

    $inner_watch->block_message( "$infile has been processed.", "duration" );

    return;
};

#----------------------------------------------------------#
# start
#----------------------------------------------------------#
my $run = AlignDB::Run->new(
    parallel => $parallel,
    jobs     => \@files,
    code     => $worker,
);
$run->run;

$stopwatch->end_message( "All files have been processed.", "duration" );

# store program running meta info to database
# this AlignDB object is just for storing meta info
END {
    AlignDB->new(
        mysql  => "$db:$server",
        user   => $username,
        passwd => $password,
    )->add_meta_stopwatch($stopwatch);
}

exit;

__END__

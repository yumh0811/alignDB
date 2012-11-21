#!/usr/bin/perl
use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Config::Tiny;
use YAML qw(Dump Load DumpFile LoadFile);

use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::MoreUtils qw(any all);
use Math::Combinatorics;
use Statistics::Descriptive;

use AlignDB::IntSpan;
use AlignDB::Stopwatch;
use AlignDB::Util qw(:all);

use FindBin;
use lib "$FindBin::Bin/../lib";
use AlignDB;
use AlignDB::Position;

#----------------------------------------------------------#
# GetOpt section
#----------------------------------------------------------#
my $Config = Config::Tiny->new;
$Config = Config::Tiny->read("$FindBin::Bin/../alignDB.ini");

# record ARGV and Config
my $stopwatch = AlignDB::Stopwatch->new(
    program_name => $0,
    program_argv => [@ARGV],
    program_conf => $Config,
);

# Database init values
my $server   = $Config->{database}{server};
my $port     = $Config->{database}{port};
my $username = $Config->{database}{username};
my $password = $Config->{database}{password};

# Database info
# Normal order: TvsR, TvsQ1, TvsQ2
my $dbs;
my $outgroup;
my $target;
my $queries;
my $goal_db;

# ref parameter
my $length_threshold = $Config->{ref}{length_threshold};
my $raw_fasta        = $Config->{ref}{raw_fasta};
my $trimmed_fasta    = $Config->{ref}{trimmed_fasta};
my $reduce_end       = $Config->{ref}{reduce_end};

my $no_insert       = 0;
my $discard_distant = 0;

my $crude_only = 0;

# realign parameters
my $indel_expand = $Config->{ref}{indel_expand};
my $indel_join   = $Config->{ref}{indel_join};

# run init_alignDB.pl or not
my $init_db = 1;

my $man  = 0;
my $help = 0;

GetOptions(
    'help|?'            => \$help,
    'man'               => \$man,
    's|server=s'        => \$server,
    'P|port=i'          => \$port,
    'u|username=s'      => \$username,
    'p|password=s'      => \$password,
    'dbs=s'             => \$dbs,
    'goal_db=s'         => \$goal_db,
    'outgroup=s'        => \$outgroup,
    'target=s'          => \$target,
    'queries=s'         => \$queries,
    'length=i'          => \$length_threshold,
    'crude_only'        => \$crude_only,
    'raw_fasta=s'       => \$raw_fasta,
    'trimmed_fasta=s'   => \$trimmed_fasta,
    'reduce_end=i'      => \$reduce_end,
    'init_db=s'         => \$init_db,
    'no_insert=s'       => \$no_insert,
    'discard_distant=s' => \$discard_distant,
    'indel_expand=i'    => \$indel_expand,
    'indel_join=i'      => \$indel_join,
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

#----------------------------------------------------------#
# perl init_alignDB.pl
#----------------------------------------------------------#
$stopwatch->start_message("Joining DBs...");

if ($crude_only) {
    $no_insert = 1;
}

if ( !$no_insert and $init_db and $goal_db ) {
    my $cmd
        = "perl $FindBin::Bin/../init/init_alignDB.pl"
        . " -s=$server"
        . " --port=$port"
        . " -d=$goal_db"
        . " -u=$username"
        . " --password=$password";
    print "\n", "=" x 12, "CMD", "=" x 15, "\n";
    print $cmd , "\n";
    print "=" x 30, "\n";
    system($cmd);
}

#----------------------------------------------------------#
# Init objects
#----------------------------------------------------------#
my @all_dbs = split ",", $dbs;
my @queries = split ",", $queries;
my @all_names = ( $outgroup, $target, @queries );
if ( scalar @all_dbs != scalar @queries + 1 ) {
    printf "DB %d\tQueries %d\n", scalar @all_dbs, scalar @queries;
    die "DB number doesn't match with species number\n";
}
elsif ( !$target ) {
    die "Target not defined\n";
}
elsif ( !$outgroup ) {
    die "Outgroup not defined\n";
}
elsif ( !scalar @queries ) {
    die "Queries not defined\n";
}

my $goal_obj;
if ( !$no_insert ) {
    $goal_obj = AlignDB->new(
        mysql  => "$goal_db:$server",
        user   => $username,
        passwd => $password,
    );
}

#----------------------------#
# info hash
#----------------------------#
my %db_info_of;
for (@all_dbs) {
    my $cur_obj = AlignDB->new(
        mysql  => "$_:$server",
        user   => $username,
        passwd => $password,
    );
    my $cur_dbh = $cur_obj->dbh;
    my $cur_pos_obj = AlignDB::Position->new( dbh => $cur_dbh );
    $db_info_of{$_} = {
        target => {
            taxon_id => '',
            name     => '',
        },
        query => {
            taxon_id => '',
            name     => '',
        },
        obj     => $cur_obj,
        pos_obj => $cur_pos_obj,
    };

    ( $db_info_of{$_}->{target}{taxon_id}, $db_info_of{$_}->{query}{taxon_id}, )
        = $cur_obj->get_taxon_ids;

    ( $db_info_of{$_}->{target}{name}, $db_info_of{$_}->{query}{name}, )
        = $cur_obj->get_names;

    my $chr_id_set = AlignDB::IntSpan->new;

    my $chr_ref = $cur_obj->get_chrs('target');

    for my $ref ( @{$chr_ref} ) {
        my ( $chr_id, $chr_name, $chr_length ) = @{$ref};
        my $chr_set = build_chr_set( $cur_dbh, $chr_id, $reduce_end );
        $db_info_of{$_}->{chrs}{$chr_id}{set}  = $chr_set;
        $db_info_of{$_}->{chrs}{$chr_id}{name} = $chr_name;
        $chr_id_set->add($chr_id);
    }
    $db_info_of{$_}->{chr_id_set} = $chr_id_set;
}

my $target_db;
{
    $target =~ /^(\d+)(.+)/;
    $target_db = $all_dbs[$1];
}

my ( undef, @ingroup_names ) = @all_names;
my %ingroup_order;
for ( 0 .. @ingroup_names - 1 ) {
    $ingroup_order{ $ingroup_names[$_] } = $_;
}

#----------------------------------------------------------#
# Init
#----------------------------------------------------------#

my $percentile_90;
if ($discard_distant) {
    $outgroup =~ /^(\d+)(.+)/;
    my $db_name = $all_dbs[$1];

    my $per_idn_query = qq{
        SELECT  a.align_identities / a.align_length
        FROM align a
    };

    my $dbh = $db_info_of{$db_name}->{dbh};
    my $sth = $dbh->prepare($per_idn_query);

    my @data;
    $sth->execute;
    while ( my @row = $sth->fetchrow_array ) {
        push @data, $row[0];
    }

    my $stat = Statistics::Descriptive::Full->new;
    $stat->add_data(@data);
    $percentile_90 = $stat->percentile($discard_distant);
}

#----------------------------------------------------------#
# Start
#----------------------------------------------------------#

#----------------------------#
# build intersect chromosome set
#----------------------------#
my %chr_set_of;
for my $chr_id ( $db_info_of{$target_db}->{chr_id_set}->elements ) {
    my ($chr_name) = $db_info_of{$target_db}->{obj}->get_chr_info($chr_id);
    print "\nchr_id: $chr_id\tchr_name: $chr_name\n";

    my $inter_chr_set = AlignDB::IntSpan->new;
    for my $db_name (@all_dbs) {
        my $cur_chr_set = $db_info_of{$db_name}->{chrs}{$chr_id}{set};
        $cur_chr_set = AlignDB::IntSpan->new unless $cur_chr_set;
        if ( $inter_chr_set->is_empty ) {
            $inter_chr_set = $cur_chr_set;
        }
        else {
            $inter_chr_set = $inter_chr_set->intersect($cur_chr_set);
        }
    }

    $chr_set_of{$chr_id} = $inter_chr_set;
}

for my $chr_id ( sort keys %chr_set_of ) {
    my $inter_chr_set = $chr_set_of{$chr_id};
    my $chr_name      = $db_info_of{$target_db}->{chrs}{$chr_id}{name};

    #----------------------------#
    # process each intersects
    #----------------------------#

    my @segments = $inter_chr_set->spans;
SEG: for (@segments) {
        my $seg_start  = $_->[0];
        my $seg_end    = $_->[1];
        my $seg_length = $seg_end - $seg_start + 1;
        next if $seg_length <= $length_threshold;

        print "$chr_name:$seg_start-$seg_end; length:$seg_length\n";

        for my $db_name (@all_dbs) {
            my $pos_obj = $db_info_of{$db_name}->{pos_obj};
            my ( $align_id, $dummy ) = @{
                $pos_obj->positioning_align_chr_id( $chr_id, $seg_start,
                    $seg_end )
                };

            if ( !defined $align_id ) {
                warn " " x 4, "Find no align in $db_name, jump to next\n";
                next SEG;
            }
            elsif ( defined $dummy ) {
                warn " " x 4, "Overlapped alignment in $db_name!\n";
            }
            $db_info_of{$db_name}->{align_id} = $align_id;
        }

        #----------------------------#
        # get seq, use align coordinates
        #----------------------------#
        for my $db_name (@all_dbs) {
            print " " x 4, "build $db_name seqs\n";
            my $align_id = $db_info_of{$db_name}->{align_id};

            my $error
                = build_seq( $db_info_of{$db_name}, $seg_start, $seg_end );
            if ($error) {
                warn $error . " in $db_name $align_id\n";
                next SEG;
            }
        }

        #----------------------------#
        # discard alignments which have low percentage identity to outgroup
        #----------------------------#
        if ($discard_distant) {
            $outgroup =~ /^(\d+)(.+)/;
            my $db_name_idx = $1;
            my $db_name     = $all_dbs[$db_name_idx];
            my $result      = pair_seq_stat(
                $db_info_of{$db_name}->{target}{seq},
                $db_info_of{$db_name}->{query}{seq},
            );
            my $seq_legnth = $result->[0];
            my $identities = $result->[2];
            my $per_idn    = $identities / $seq_legnth;
            if ( $per_idn >= $percentile_90 ) {
                warn " " x 4 . "Low percentage identity with outgroup\n";
                next SEG;
            }
        }

        #----------------------------#
        # start peusdo-alignment, according to common sequences
        #----------------------------#
        print " " x 4, "start peusdo-alignment\n";
        my $pos_count = 0;
        while (1) {
            $pos_count++;
            my $max_length = 0;
            for my $db_name (@all_dbs) {
                $max_length = max( $max_length,
                    length $db_info_of{$db_name}->{target}{seq} );
            }
            if ( $pos_count >= $max_length ) {
                last;
            }

            my @target_bases;
            for my $db_name (@all_dbs) {
                push @target_bases,
                    substr( $db_info_of{$db_name}->{target}{seq},
                    $pos_count - 1, 1 );
            }

            if ( all { $_ eq $target_bases[0] } @target_bases ) {
                next;
            }
            elsif ( all { $_ ne '-' } @target_bases ) {
                warn " " x 8 . "align error in $pos_count, [@target_bases]\n";

                #my %target_seq_of
                #    = map { $_ => $db_info_of{$_}->{target}{seq} } @all_dbs;
                #DumpFile( "$chr_name-$seg_start-$seg_end.yml",
                #    \%target_seq_of );
                next SEG;
            }

            # insert a '-' in current position
            for ( 0 .. @all_dbs - 1 ) {
                my $db_name = $all_dbs[$_];
                if ( $target_bases[$_] eq '-' ) {
                    next;
                }
                else {
                    substr(
                        $db_info_of{$db_name}->{target}{seq},
                        $pos_count - 1,
                        0, '-'
                    );
                    substr(
                        $db_info_of{$db_name}->{query}{seq},
                        $pos_count - 1,
                        0, '-'
                    );
                }
            }
        }

        #----------------------------#
        # build %info_of all_names hash
        #----------------------------#
        my %info_of;
        for my $name (@all_names) {
            $name =~ /^(\d+)(.+)/;
            my $db_name_idx = $1;
            my $torq        = $2;
            if ( not( $torq =~ /^t/i or $torq =~ /^q/i ) ) {
                die "$torq is not equal to target or query\n";
            }
            my $db_name = $all_dbs[$db_name_idx];
            $info_of{$name} = $db_info_of{$db_name}->{$torq};
        }

        #----------------------------#
        # output peusdo-aligned fasta, need be refined later
        # skip all processing thereafter
        #----------------------------#
        if ($crude_only) {
            my $goal_db_crude = "$goal_db.crude";
            unless ( -e $goal_db_crude ) {
                mkdir $goal_db_crude, 0777
                    or die "Cannot create [$goal_db_crude] directory: $!";
            }
            my $first_taxon_id = $info_of{ $all_names[1] }->{taxon_id};
            my $outfile
                = "./$goal_db_crude/"
                . "id$first_taxon_id"
                . "_$chr_name"
                . "_$seg_start"
                . "_$seg_end" . ".fas";
            print " " x 4, "$outfile\n";
            open my $out_fh, '>', $outfile
                or die("Cannot open output file $outfile");
            for my $name (@all_names) {
                my $seq = $info_of{$name}->{seq};
                print {$out_fh} ">", $info_of{$name}->{name}, "\n";
                print {$out_fh} $seq, "\n";
            }
            close $out_fh;

            next SEG;
        }

        #----------------------------#
        # clustalw realign indel_flank region
        #----------------------------#
        {
            print " " x 4, "start finding realign region\n";
            realign( \%info_of, \@all_names );
        }

        #----------------------------#
        # output a raw fasta alignment for further use
        #----------------------------#
        if ($raw_fasta) {
            my $goal_db_raw = "$goal_db.raw";
            unless ( -e $goal_db_raw ) {
                mkdir $goal_db_raw, 0777
                    or die "Cannot create [$goal_db_raw] directory: $!";
            }
            my $first_taxon_id = $info_of{ $all_names[1] }->{taxon_id};
            my $outfile
                = "./$goal_db_raw/"
                . "id$first_taxon_id"
                . "_$chr_name"
                . "_$seg_start"
                . "_$seg_end" . ".fas";
            print " " x 4, "$outfile\n";
            open my $out_fh, '>', $outfile
                or die("Cannot open output file $outfile");
            for my $name (@all_names) {
                my $seq = $info_of{$name}->{seq};
                print {$out_fh} ">", $info_of{$name}->{name}, "\n";
                print {$out_fh} $seq, "\n";
            }
            close $out_fh;
        }

        #----------------------------#
        # trim outgroup only sequence
        #----------------------------#
        # if intersect is superset of union
        #   ref    GAAAAC
        #   target G----C
        #   query  G----C
        {
            trim_outgroup( \%info_of, \@all_names );
        }

        #----------------------------#
        # trim header and footer indels
        #----------------------------#
        {
            trim_hf( \%info_of, \@all_names );
        }

        #----------------------------#
        # record complex indels and ingroup indels
        #----------------------------#
        # if intersect is subset of union
        #   ref GGAGAC
        #   tar G-A-AC
        #   que G----C
        {
            my $complex_region = AlignDB::IntSpan->new;

            # don't expand indel set
            my %indel_sets;
            for (@all_names) {
                $indel_sets{$_} = find_indel_set( $info_of{$_}->{seq} );
            }
            my $outgroup_indel_set = $indel_sets{$outgroup};
            delete $indel_sets{$outgroup};

            # all ingroup intersect sets are complex region after remove
            # uniform ingroup indels
            my $union_set = AlignDB::IntSpan::union( values %indel_sets );
            my $intersect_set
                = AlignDB::IntSpan::intersect( values %indel_sets );

            for ( reverse $intersect_set->spans ) {
                my $seg_start = $_->[0];
                my $seg_end   = $_->[1];

                # trim sequence
                for (@all_names) {
                    substr(
                        $info_of{$_}->{seq},
                        $seg_start - 1,
                        $seg_end - $seg_start + 1, ''
                    );
                }
                print " " x 4,
                    "Delete complex trim region $seg_start - $seg_end\n";

                # add to complex_region
                for my $span ( $union_set->runlists ) {
                    my $sub_union_set = AlignDB::IntSpan->new($span);
                    if ( $sub_union_set->superset("$seg_start-$seg_end") ) {
                        $complex_region->merge($sub_union_set);
                    }
                }

                # modify all related set
                $union_set = $union_set->banish_span( $seg_start, $seg_end );
                for (@ingroup_names) {
                    $indel_sets{$_}
                        = $indel_sets{$_}->banish_span( $seg_start, $seg_end );
                }
                $outgroup_indel_set->banish_span( $seg_start, $seg_end );
                $complex_region
                    = $complex_region->banish_span( $seg_start, $seg_end );
            }

            # add ingroup-outgroup complex indels to complex_region
            # and record ingroup indels
            my $all_indel_region = AlignDB::IntSpan->new;
            for my $name (@ingroup_names) {
                $all_indel_region->merge( $indel_sets{$name} );
                my $outgroup_intersect_set
                    = $outgroup_indel_set->intersect( $indel_sets{$name} );
                for my $out_span ( $outgroup_intersect_set->runlists ) {

                    for my $union_span ( $union_set->runlists ) {
                        my $sub_union_set = AlignDB::IntSpan->new($union_span);

                        # union_set > intersect_set
                        if ( $sub_union_set->larger_than($out_span) ) {
                            $complex_region->merge($sub_union_set);
                        }
                    }
                }
            }

            # record complex indel info to $info{$outgroup}
            $info_of{$outgroup}->{complex} = $complex_region->runlist;

            # record all ingroup indel info to $info{$outgroup}
            $info_of{$outgroup}->{all_indel} = $all_indel_region->runlist;
        }

        #----------------------------#
        # output a fasta alignment for further use
        #----------------------------#
        if ($trimmed_fasta) {
            unless ( -e $goal_db ) {
                mkdir $goal_db, 0777
                    or die "Cannot create \"$goal_db\" directory: $!";
            }
            my $first_taxon_id = $info_of{ $all_names[1] }->{taxon_id};
            my $outfile
                = "./$goal_db/"
                . "id$first_taxon_id"
                . "_$chr_name"
                . "_$seg_start"
                . "_$seg_end" . ".fas";
            print " " x 4, "$outfile\n";
            open my $out_fh, '>', $outfile
                or die("Cannot open OUT file $outfile");
            for my $name (@all_names) {
                my $seq = $info_of{$name}->{seq};
                print {$out_fh} ">", $info_of{$name}->{name}, "\n";
                print {$out_fh} $seq, "\n";
            }
            close $out_fh;
        }

        if ( !$no_insert ) {
            my @align_ids;
            my $combinat = Math::Combinatorics->new(
                count => 2,
                data  => \@ingroup_names,
            );
            while ( my @combo = $combinat->next_combination ) {
                @combo
                    = sort { $ingroup_order{$a} <=> $ingroup_order{$b} } @combo;
                my ( $tname, $qname ) = @combo;
                print "insert $tname $qname\n";
                my $cur_align_id
                    = $goal_obj->add_align( $info_of{$tname}, $info_of{$qname},
                    $info_of{$outgroup}, $info_of{$outgroup}->{all_indel} );
                push @align_ids, $cur_align_id;
            }
        }
    }
}

$stopwatch->end_message;

# store program running meta info to database
END {
    if ( !$no_insert ) {
        $goal_obj->add_meta_stopwatch($stopwatch);
    }
}
exit;

sub build_chr_set {
    my $dbh        = shift;
    my $chr_id     = shift;
    my $reduce_end = shift || 0;

    my $chr_set = AlignDB::IntSpan->new;

    my $chr_query = qq{
        SELECT  s.chr_start + $reduce_end,
                s.chr_end - $reduce_end
        FROM sequence s, chromosome c
        WHERE c.chr_id = ?
        AND s.chr_id = c.chr_id
    };

    # build $chr_set
    my $chr_sth = $dbh->prepare($chr_query);
    $chr_sth->execute($chr_id);
    while ( my @row = $chr_sth->fetchrow_array ) {
        my ( $chr_start, $chr_end ) = @row;
        next if $chr_start > $chr_end;
        $chr_set->add_range( $chr_start, $chr_end );
    }

    return $chr_set;
}

# get seq, use align coordinates
sub build_seq {
    my $db_info   = shift;
    my $seg_start = shift;
    my $seg_end   = shift;

    my $obj      = $db_info->{obj};
    my $pos_obj  = $db_info->{pos_obj};
    my $align_id = $db_info->{align_id};

    my $target_info = $obj->get_target_info($align_id);
    $db_info->{target}{chr_id}     = $target_info->{chr_id};
    $db_info->{target}{chr_name}   = $target_info->{chr_name};
    $db_info->{target}{chr_strand} = $target_info->{chr_strand};

    my $query_info = $obj->get_query_info($align_id);
    $db_info->{query}{chr_id}       = $query_info->{chr_id};
    $db_info->{target}{chr_name}    = $target_info->{chr_name};
    $db_info->{query}{chr_strand}   = $query_info->{chr_strand};
    $db_info->{query}{query_strand} = $query_info->{query_strand};

    ( $db_info->{target}{full_seq}, $db_info->{query}{full_seq} )
        = @{ $obj->get_seqs($align_id) };

    my $align_start = $pos_obj->at_align( $align_id, $seg_start );
    my $align_end   = $pos_obj->at_align( $align_id, $seg_end );

    # align_start and align_end should must be available
    unless ( $align_start and $align_end ) {
        return " " x 8 . "align_start or align_end error";
    }

    my $align_length = $align_end - $align_start + 1;

    # target chr position
    $db_info->{target}{chr_start} = $seg_start;
    $db_info->{target}{chr_end}   = $seg_end;

    # query chr position
    $db_info->{query}{chr_start}
        = $pos_obj->at_query_chr( $align_id, $align_start );
    $db_info->{query}{chr_end}
        = $pos_obj->at_query_chr( $align_id, $align_end );

    $db_info->{target}{seq}
        = substr( $db_info->{target}{full_seq}, $align_start - 1,
        $align_length );
    $db_info->{query}{seq}
        = substr( $db_info->{query}{full_seq}, $align_start - 1,
        $align_length );

    unless (length $db_info->{target}{seq} == length $db_info->{query}{seq}
        and length $db_info->{target}{seq} > 0 )
    {
        return " " x 8 . "seq-length error";
    }

    delete $db_info->{target}{full_seq};
    delete $db_info->{query}{full_seq};

    return;
}

#----------------------------#
# clustalw realign indel_flank region
#----------------------------#
sub realign {
    my $info_of   = shift;
    my $all_names = shift;

    my %info_of = %{$info_of};

    # use AlignDB::IntSpan to find nearby indels
    #   expand indel by a range of $indel_expand

    my %indel_sets;
    for (@$all_names) {
        $indel_sets{$_} = find_indel_set( $info_of{$_}->{seq}, $indel_expand );
    }

    my $realign_region = AlignDB::IntSpan->new;
    my $combinat       = Math::Combinatorics->new(
        count => 2,
        data  => $all_names,
    );
    while ( my @combo = $combinat->next_combination ) {
        my $intersect_set = AlignDB::IntSpan->new;
        my $union_set     = AlignDB::IntSpan->new;
        $intersect_set
            = $indel_sets{ $combo[0] }->intersect( $indel_sets{ $combo[1] } );
        $union_set
            = $indel_sets{ $combo[0] }->union( $indel_sets{ $combo[1] } );

        for my $span ( $union_set->runlists ) {
            my $flag_set = $intersect_set->intersect($span);
            if ( $flag_set->is_not_empty ) {
                $realign_region->add($span);
            }
        }
    }

    # join adjacent realign regions
    $realign_region = $realign_region->join_span($indel_join);

    # realign all segments in realign_region
    my @realign_region_spans = $realign_region->spans;
    for ( reverse @realign_region_spans ) {
        my $seg_start = $_->[0];
        my $seg_end   = $_->[1];
        my @segments;
        for (@$all_names) {
            my $seg = substr(
                $info_of{$_}->{seq},
                $seg_start - 1,
                $seg_end - $seg_start + 1
            );
            push @segments, $seg;
        }

        my $realign_segments = clustal_align( \@segments );

        for (@$all_names) {
            my $seg = shift @$realign_segments;
            substr(
                $info_of{$_}->{seq},
                $seg_start - 1,
                $seg_end - $seg_start + 1, $seg
            );
        }
    }

    $info_of = \%info_of;
}

#----------------------------#
# trim header and footer indels
#----------------------------#
sub trim_hf {
    my $info_of   = shift;
    my $all_names = shift;

    my %info_of = %{$info_of};

    # header indels
    while (1) {
        my @first_column;
        for (@$all_names) {
            my $first_base = substr( $info_of{$_}->{seq}, 0, 1 );
            push @first_column, $first_base;
        }
        if ( all { $_ eq '-' } @first_column ) {
            for (@$all_names) {
                substr( $info_of{$_}->{seq}, 0, 1, '' );
            }
            print " " x 4, "Trim header indel\n";
        }
        else {
            last;
        }
    }

    # footer indels
    while (1) {
        my (@last_column);
        for (@$all_names) {
            my $last_base = substr( $info_of{$_}->{seq}, -1, 1 );
            push @last_column, $last_base;
        }
        if ( all { $_ eq '-' } @last_column ) {
            for (@$all_names) {
                substr( $info_of{$_}->{seq}, -1, 1, '' );
            }
            print " " x 4, "Trim footer indel\n";
        }
        else {
            last;
        }
    }

    $info_of = \%info_of;
}

#----------------------------#
# trim outgroup only sequence
#----------------------------#
# if intersect is superset of union
#   ref    GAAAAC
#   target G----C
#   query  G----C
sub trim_outgroup {
    my $info_of   = shift;
    my $all_names = shift;

    my %info_of = %{$info_of};

    # add raw_seqs to outgroup info hash
    # it will be used in $goal_obj->add_align
    $info_of{$outgroup}->{raw_seq} = $info_of{$outgroup}->{seq};

    # don't expand indel set
    my %indel_sets;
    for ( 1 .. @$all_names - 1 ) {
        my $name = $all_names->[$_];
        $indel_sets{$name} = find_indel_set( $info_of{$name}->{seq} );
    }

    # find trim_region
    my $trim_region = AlignDB::IntSpan->new;

    my $union_set     = AlignDB::IntSpan::union( values %indel_sets );
    my $intersect_set = AlignDB::IntSpan::intersect( values %indel_sets );

    for my $span ( $union_set->runlists ) {
        if ( $intersect_set->superset($span) ) {
            $trim_region->add($span);
        }
    }

    # trim all segments in trim_region
    print " " x 4, "Delete trim region\n" if $trim_region->is_not_empty;
    for ( reverse $trim_region->spans ) {
        my $seg_start = $_->[0];
        my $seg_end   = $_->[1];
        for (@$all_names) {
            substr(
                $info_of{$_}->{seq},
                $seg_start - 1,
                $seg_end - $seg_start + 1, ''
            );
        }
    }

    $info_of = \%info_of;
}

__END__

=head1 NAME

    join_dbs.pl - join multiple dbs for three-lineage test or maligndb

=head1 SYNOPSIS

    perl join_dbs.pl [options]
      Options:
        --help              brief help message
        --man               full documentation
        --server            MySQL server IP/Domain name
        --port              MySQL server port
        --username          username
        --password          password
        --dbs               DB names list seperated by ','
        --goal_db           goal database name
        --outgroup          outgroup identity (0query)
        --target            target identity (0target)
        --queries           query list (1query,2query)
        --length            threshold of alignment length
        --realign           correct pesudo-alignment error
        --raw_fasta         save raw fasta files
        --trimmed_fasta     save ref-trimmed fasta files
        --reduce_end        reduce align end to avoid some overlaps in
                              BlastZ results (use 10 instead of 0)
                            For two independent datasets, use 10;
                            for two dependent datasets, use 0
        --init_db           call init_alignDB.pl
        --no_insert         don't insert into goal_db actually
        --discard_distant
        --indel_expand
        --indel_join

$ perl join_dbs.pl --dbs S288CvsSpar,S288CvsRM11,S288CvsYJM789 \
--goal_db S288CvsThree --no_insert=1 --trimmed_fasta=1 \
--outgroup 0query --target 0target --queries 1query,2query

$ perl join_dbs.pl --dbs S288CvsSpar,S288CvsRM11 --goal_db S288CvsRM11refSpar --outgroup 0query --target 0target --queries 1query

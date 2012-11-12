#!/usr/bin/perl
use strict;
use warnings;

use DBI;
use Getopt::Long;
use Pod::Usage;
use YAML qw(Dump Load DumpFile LoadFile);

use FindBin;
use AlignDB::SQL;
use AlignDB::SQL::Library;

#----------------------------------------------------------#
# SQL
#----------------------------------------------------------#

# Object headers in sql_library are named under the following rules:
#   TYEP-NAME-BINDINGs
# e.g.: common-distance-0
#       three-distance-0

#----------------------------------------------------------#
# GetOpt section
#----------------------------------------------------------#
my $lib_file = "$FindBin::Bin/sql.lib";

my $verbose;

my $man  = 0;
my $help = 0;

GetOptions(
    'help|?'  => \$help,
    'man'     => \$man,
    'lib=s'   => \$lib_file,
    'verbose' => \$verbose,
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

#----------------------------------------------------------#
# Init section
#----------------------------------------------------------#
unlink $lib_file if -e $lib_file;
my $sql_file = AlignDB::SQL::Library->new( lib => $lib_file );

sub ns { return AlignDB::SQL->new; }

#----------------------------------------------------------#
# stat_factory.pl SQL
#----------------------------------------------------------#

#SELECT isw_distance distance,
#       AVG(isw_pi) AVG_pi,
#       COUNT(*) COUNT,
#       STD(isw_pi) STD_pi
#FROM isw
#GROUP BY isw_distance
{
    my $sql = ns();
    $sql->add_select( 'isw_distance', 'distance' );
    $sql->add_select( 'AVG(isw_pi)',  'AVG_pi' );
    $sql->add_select( 'COUNT(*)',     'COUNT' );
    $sql->add_select( 'STD(isw_pi)',  'STD_pi' );
    $sql->from( ['isw'] );
    $sql->group( { column => 'isw_distance' } );

    $sql_file->set( 'common-distance-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT 'Total',
#       AVG(isw_pi) AVG_pi,
#       COUNT(*) COUNT,
#       STD(isw_pi) STD_pi
#FROM isw
{
    my $sql = ns();
    $sql->select( ['\'Total\''] );
    $sql->add_select( 'AVG(isw_pi)', 'AVG_pi' );
    $sql->add_select( 'COUNT(*)',    'COUNT' );
    $sql->add_select( 'STD(isw_pi)', 'STD_pi' );
    $sql->from( ['isw'] );

    $sql_file->set( 'common-distance_total-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT isw_distance distance,
#       COUNT(*) COUNT,
#       SUM(isw_length) SUM_length
#FROM isw
#GROUP BY isw_distance
{
    my $sql = ns();
    $sql->add_select( 'isw_distance',    'distance' );
    $sql->add_select( 'COUNT(*)',        'COUNT' );
    $sql->add_select( 'SUM(isw_length)', 'SUM_length' );
    $sql->from( ['isw'] );
    $sql->group( { column => 'isw_distance' } );

    $sql_file->set( 'common-distance_combine-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT AVG(isw_distance) AVG_distance,
#       AVG(isw_pi) AVG_pi,
#       COUNT(*) COUNT,
#       STD(isw_pi) STD_pi
#FROM isw
{
    my $sql = ns();
    $sql->add_select( 'AVG(isw_distance)', 'AVG_distance' );
    $sql->add_select( 'AVG(isw_pi)',       'AVG_pi' );
    $sql->add_select( 'COUNT(*)',          'COUNT' );
    $sql->add_select( 'STD(isw_pi)',       'STD_pi' );
    $sql->from( ['isw'] );

    $sql_file->set( 'common-distance_avg-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT
#  isw.isw_distance distance,
#  COUNT(*) COUNT
#FROM
#WHERE (isw.isw_coding >= ?)
#  AND (isw.isw_coding <= ?)
{
    my $sql = ns();
    $sql->add_select( 'isw.isw_distance', 'distance' );
    $sql->add_select( 'COUNT(*)',         'COUNT' );

    $sql->from( ['isw'] );
    $sql->add_where( 'isw.isw_coding' => { op => '>=', value => '1' } );
    $sql->add_where( 'isw.isw_coding' => { op => '<=', value => '1' } );
    $sql->group( { column => 'isw.isw_distance' } );

    $sql_file->set( 'common-distance_coding_combine-2', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT
#  AVG(isw.isw_distance) AVG_distance,
#  AVG(isw.isw_pi) AVG_pi,
#  COUNT(*) COUNT,
#  STD(isw.isw_pi) STD_pi
#FROM
#WHERE (isw.isw_coding >= ?)
#  AND (isw.isw_coding <= ?)
{
    my $sql = ns();
    $sql->add_select( 'AVG(isw.isw_distance)', 'AVG_distance' );
    $sql->add_select( 'AVG(isw.isw_pi)',       'AVG_pi' );
    $sql->add_select( 'COUNT(*)',              'COUNT' );
    $sql->add_select( 'STD(isw.isw_pi)',       'STD_pi' );

    $sql->from( ['isw'] );
    $sql->add_where( 'isw.isw_coding' => { op => '>=', value => '1' } );
    $sql->add_where( 'isw.isw_coding' => { op => '<=', value => '1' } );

    $sql_file->set( 'common-distance_coding-2', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT CONCAT(isw_type, isw_distance) isw_type_distance,
#       AVG(isw_pi) AVG_pi,
#       COUNT(isw_pi) COUNT,
#       STD(isw_pi) STD_pi
#FROM isw
#WHERE isw_type = ?
#AND isw_density BETWEEN ? AND ?
#AND isw_distance <= (? + 1) / 2
#GROUP BY CONCAT(isw_type, isw_distance)
#ORDER BY isw_distance
{
    my $sql = ns();
    $sql->add_select( 'CONCAT(isw_type, isw_distance)', 'isw_type_distance' );
    $sql->add_select( 'AVG(isw_pi)',                    'AVG_pi' );
    $sql->add_select( 'COUNT(*)',                       'COUNT' );
    $sql->add_select( 'STD(isw_pi)',                    'STD_pi' );
    $sql->from( ['isw'] );
    $sql->add_where( 'isw_type'     => 'L' );
    $sql->add_where( 'isw_density'  => { op => '>=', value => '1' } );
    $sql->add_where( 'isw_density'  => { op => '<=', value => '2' } );
    $sql->add_where( 'isw_distance' => \'<= (? + 1) / 2' );

    $sql->group( { column => 'CONCAT(isw_type, isw_distance)' } );
    $sql->order( { column => 'isw_distance' } );

    $sql_file->set( 'common-dd_group-4', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT CONCAT(isw.isw_type, isw.isw_distance) isw_type_distance,
#       AVG(isw_pi) AVG_pi,
#       COUNT(isw_pi) COUNT,
#       STD(isw_pi) STD_pi
#FROM indel INNER JOIN isw ON indel.indel_id = isw.indel_id
#WHERE isw.isw_density > 9
#AND isw.isw_distance <= 5
#AND isw.isw_type = 'R'
##AND indel.indel_length >= ?
##AND indel.indel_length <= ?
#GROUP BY CONCAT(isw.isw_type, isw.isw_distance) DESC
{
    my $sql = ns();
    $sql->add_select( 'CONCAT(isw_type, isw_distance)', 'isw_type_distance' );
    $sql->add_select( 'AVG(isw.isw_pi)',                'AVG_pi' );
    $sql->add_select( 'COUNT(*)',                       'COUNT' );
    $sql->add_select( 'STD(isw.isw_pi)',                'STD_pi' );
    $sql->add_where( 'isw.isw_density'  => \'> 9' );
    $sql->add_where( 'isw.isw_distance' => \'<= 5' );

    #$sql->add_where( 'indel.indel_length' => { op => '>=', value => '1' } );
    #$sql->add_where( 'indel.indel_length' => { op => '<=', value => '5' } );

    my $sql_R = $sql->copy;
    $sql_R->add_join(
        indel => {
            type      => 'inner',
            table     => 'isw',
            condition => 'indel.indel_id = isw.indel_id',
        }
    );
    $sql_R->add_where( 'isw.isw_type' => \'= \'R\'' );
    $sql_R->group(
        {   column => 'CONCAT(isw.isw_type, isw.isw_distance)',
            desc   => 'DESC'
        }
    );

    my $sql_L = $sql->copy;
    $sql_L->add_join(
        indel => {
            type      => 'inner',
            table     => 'isw',
            condition => 'indel.indel_id = isw.prev_indel_id',
        }
    );
    $sql_L->add_where( 'isw.isw_type' => \'= \'L\'' );
    $sql_L->group( { column => 'CONCAT(isw.isw_type, isw.isw_distance)' } );

    $sql_file->set( 'common-indel_size_r-0', $sql_R->freeze );
    $sql_file->set( 'common-indel_size_l-0', $sql_L->freeze );
    print $sql_R->as_sql if $verbose;
    print $sql_L->as_sql if $verbose;
}

#SELECT
#  CONCAT(isw_type, isw_distance) isw_type_distance,
#  AVG(isw.isw_pi) AVG_pi,
#  COUNT(*) COUNT,
#  STD(isw.isw_pi) STD_pi
#FROM indel
#  INNER JOIN isw ON
#    indel.indel_id = isw.indel_id
#WHERE (isw.isw_density > 9)
#  AND (isw.isw_distance <= 5)
#  AND (isw.isw_type = 'R')
#GROUP BY
#  CONCAT(isw.isw_type, isw.isw_distance) DESC
{
    my $sql = ns();
    $sql->add_select( 'CONCAT(isw_type, isw_distance)', 'isw_type_distance' );
    $sql->add_select( 'AVG(isw.isw_pi)',                'AVG_pi' );
    $sql->add_select( 'COUNT(*)',                       'COUNT' );
    $sql->add_select( 'STD(isw.isw_pi)',                'STD_pi' );
    $sql->add_where( 'isw.isw_density'  => \'> 9' );
    $sql->add_where( 'isw.isw_distance' => \'<= 5' );

    my $sql_R = $sql->copy;
    $sql_R->add_join(
        indel => [
            {   type      => 'inner',
                table     => 'isw',
                condition => 'indel.indel_id = isw.indel_id',
            },
        ]
    );
    $sql_R->add_where( 'isw.isw_type' => \'= \'R\'' );
    $sql_R->group(
        {   column => 'CONCAT(isw.isw_type, isw.isw_distance)',
            desc   => 'DESC'
        }
    );

    my $sql_L = $sql->copy;
    $sql_L->add_join(
        indel => [
            {   type      => 'inner',
                table     => 'isw',
                condition => 'indel.indel_id = isw.prev_indel_id',
            },
        ]
    );
    $sql_L->add_where( 'isw.isw_type' => \'= \'L\'' );
    $sql_L->group( { column => 'CONCAT(isw.isw_type, isw.isw_distance)' } );

    $sql_file->set( 'common-indel_feature_r-0', $sql_R->freeze );
    $sql_file->set( 'common-indel_feature_l-0', $sql_L->freeze );
    print $sql_R->as_sql if $verbose;
    print $sql_L->as_sql if $verbose;
}

#SELECT  indel_length,
#        COUNT(*) indel_number,
#        AVG(indel_gc) AVG_gc,
#        SUM(indel_length) indel_sum
#FROM indel
#GROUP BY indel_length
{
    my $sql = ns();
    $sql->add_select('indel_length');
    $sql->add_select( 'COUNT(*)',          'indel_number' );
    $sql->add_select( 'AVG(indel_gc)',     'AVG_indel_gc' );
    $sql->add_select( 'SUM(indel_length)', 'indel_sum' );
    $sql->from( ['indel'] );
    $sql->group( { column => 'indel_length' } );

    $sql_file->set( 'common-indel_length-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT
#  isw.isw_distance distance,
#  AVG(isw.isw_pi) AVG_pi,
#  COUNT(*) COUNT,
#  STD(isw.isw_pi) STD_pi
#FROM isw
#  INNER JOIN indel i1 ON
#    isw.indel_id = i1.indel_id
#  INNER JOIN indel i2 ON
#    isw.prev_indel_id = i2.indel_id
#WHERE (isw.isw_type IN ('S'))
#  AND (i1.indel_slippage >= ?)
#  AND (i1.indel_slippage <= ?)
#  AND (i2.indel_slippage >= ?)
#  AND (i2.indel_slippage <= ?)
#GROUP BY
#  isw.isw_distance
{
    my $sql = ns();
    $sql->add_select( 'isw.isw_distance', 'distance' );
    $sql->add_select( 'AVG(isw.isw_pi)',  'AVG_pi' );
    $sql->add_select( 'COUNT(*)',         'COUNT' );
    $sql->add_select( 'STD(isw.isw_pi)',  'STD_pi' );

    $sql->add_join(
        isw => [
            {   type      => 'inner',
                table     => 'indel i1',
                condition => 'isw.indel_id = i1.indel_id',
            },
            {   type      => 'inner',
                table     => 'indel i2',
                condition => 'isw.prev_indel_id = i2.indel_id',
            },
        ]
    );
    $sql->add_where( 'isw.isw_type'      => \q{IN ('S')} );
    $sql->add_where( 'i1.indel_slippage' => { op => '>=', value => '1' } );
    $sql->add_where( 'i1.indel_slippage' => { op => '<=', value => '1' } );
    $sql->add_where( 'i2.indel_slippage' => { op => '>=', value => '1' } );
    $sql->add_where( 'i2.indel_slippage' => { op => '<=', value => '1' } );
    $sql->group( { column => 'isw.isw_distance' } );

    $sql_file->set( 'common-distance_slip_s-4', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT
#  isw.isw_distance distance,
#  AVG(isw.isw_pi) AVG_pi,
#  COUNT(*) COUNT,
#  STD(isw.isw_pi) STD_pi
#FROM isw
#  INNER JOIN indel ON
#    isw.isw_indel_id = indel.indel_id
#WHERE (isw.isw_type IN ('L', 'R'))
#  AND (indel.indel_slippage >= ?)
#  AND (indel.indel_slippage <= ?)
#GROUP BY
#  isw.isw_distance
{
    my $sql = ns();
    $sql->add_select( 'isw.isw_distance', 'distance' );
    $sql->add_select( 'AVG(isw.isw_pi)',  'AVG_pi' );
    $sql->add_select( 'COUNT(*)',         'COUNT' );
    $sql->add_select( 'STD(isw.isw_pi)',  'STD_pi' );

    $sql->add_join(
        isw => {
            type      => 'inner',
            table     => 'indel',
            condition => 'isw.isw_indel_id = indel.indel_id',
        }
    );
    $sql->add_where( 'isw.isw_type'         => \q{IN ('L', 'R')} );
    $sql->add_where( 'indel.indel_slippage' => { op => '>=', value => '1' } );
    $sql->add_where( 'indel.indel_slippage' => { op => '<=', value => '1' } );
    $sql->group( { column => 'isw.isw_distance' } );

    $sql_file->set( 'common-distance_slip_lr-2', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT
#  'Total',
#  AVG(isw_pi) AVG_pi,
#  COUNT(*) COUNT,
#  STD(isw_pi) STD_pi
#FROM isw
#  INNER JOIN indel ON
#    isw.isw_indel_id = indel.indel_id
#WHERE (isw.isw_type IN ('L', 'R'))
#  AND (indel.indel_slippage >= ?)
#  AND (indel.indel_slippage <= ?)
{
    my $sql = ns();
    $sql->select( ['\'Total\''] );
    $sql->add_select( 'AVG(isw_pi)', 'AVG_pi' );
    $sql->add_select( 'COUNT(*)',    'COUNT' );
    $sql->add_select( 'STD(isw_pi)', 'STD_pi' );

    $sql->add_join(
        isw => {
            type      => 'inner',
            table     => 'indel',
            condition => 'isw.isw_indel_id = indel.indel_id',
        }
    );
    $sql->add_where( 'isw.isw_type'         => \q{IN ('L', 'R')} );
    $sql->add_where( 'indel.indel_slippage' => { op => '>=', value => '1' } );
    $sql->add_where( 'indel.indel_slippage' => { op => '<=', value => '1' } );

    $sql_file->set( 'common-distance_slip_total-2', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT
#  isw.isw_distance distance,
#  AVG(isw.isw_pi) AVG_pi,
#  COUNT(*) COUNT,
#  STD(isw.isw_pi) STD_pi
#FROM indel
#  INNER JOIN isw ON
#    isw.indel_id = indel.indel_id
#  INNER JOIN align ON
#    align.align_id = indel.align_id
{
    my $sql = ns();
    $sql->add_select( 'isw.isw_distance', 'distance' );
    $sql->add_select( 'AVG(isw.isw_pi)',  'AVG_pi' );
    $sql->add_select( 'COUNT(*)',         'COUNT' );
    $sql->add_select( 'STD(isw.isw_pi)',  'STD_pi' );

    $sql->add_join(
        indel => [
            {   type      => 'inner',
                table     => 'isw',
                condition => 'isw.indel_id = indel.indel_id',
            },
            {   type      => 'inner',
                table     => 'align',
                condition => 'align.align_id = indel.align_id',
            },
        ]
    );

    $sql->group( { column => 'isw.isw_distance' } );

    $sql_file->set( 'common-align-0', $sql );
    print $sql->as_sql if $verbose;
}

#----------------------------------------------------------#
# three_stat_factory.pl SQL
#----------------------------------------------------------#

#SELECT isw_distance distance,
#       AVG(isw_pi) AVG_pi,
#       AVG(isw_d_indel) AVG_d_indel,
#       AVG(isw_d_noindel) AVG_d_noindel,
#       AVG(isw_d_complex) AVG_d_complex,
#       COUNT(*) COUNT,
#       AVG(isw_d_indel) / AVG(isw_d_noindel)  `Di/Dn`
#FROM isw i
#WHERE isw_distance >= 0
#AND isw_d_indel IS NOT NULL
#GROUP BY isw_distance
{
    my $sql = ns();
    $sql->add_select( 'isw_distance',       'distance' );
    $sql->add_select( 'AVG(isw_pi)',        'AVG_pi' );
    $sql->add_select( 'AVG(isw_d_indel)',   'AVG_d_indel' );
    $sql->add_select( 'AVG(isw_d_noindel)', 'AVG_d_noindel' );
    $sql->add_select( 'AVG(isw_d_complex)', 'AVG_d_complex' );
    $sql->add_select( 'COUNT(*)',           'COUNT' );
    $sql->add_select( 'AVG(isw_d_indel) / AVG(isw_d_noindel)', '`Di/Dn`' );
    $sql->from( ['isw'] );
    $sql->add_where( 'isw_distance' => \'>= 0' );
    $sql->add_where( 'isw_d_indel'  => \'IS NOT NULL' );
    $sql->group( { column => 'isw_distance' } );

    $sql_file->set( 'three-distance-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT 'Total',
#       AVG(isw_pi) AVG_pi,
#       AVG(isw_d_indel) AVG_d_indel,
#       AVG(isw_d_noindel) AVG_d_noindel,
#       AVG(isw_d_complex) AVG_d_complex,
#       COUNT(*) COUNT,
#       AVG(isw_d_indel) / AVG(isw_d_noindel)  `Di/Dn`
#FROM isw i
#WHERE isw_distance >= 0
#AND isw_d_indel IS NOT NULL
{
    my $sql = ns();
    $sql->select( ['\'Total\''] );
    $sql->add_select( 'AVG(isw_pi)',        'AVG_pi' );
    $sql->add_select( 'AVG(isw_d_indel)',   'AVG_d_indel' );
    $sql->add_select( 'AVG(isw_d_noindel)', 'AVG_d_noindel' );
    $sql->add_select( 'AVG(isw_d_complex)', 'AVG_d_complex' );
    $sql->add_select( 'COUNT(*)',           'COUNT' );
    $sql->add_select( 'AVG(isw_d_indel) / AVG(isw_d_noindel)', '`Di/Dn`' );
    $sql->from( ['isw'] );
    $sql->add_where( 'isw_distance' => \'>= 0' );
    $sql->add_where( 'isw_d_indel'  => \'IS NOT NULL' );

    $sql_file->set( 'three-distance_total-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT AVG(isw_distance) AVG_distance,
#       AVG(isw_pi) AVG_pi,
#       AVG(isw_d_indel) AVG_d_indel,
#       AVG(isw_d_noindel) AVG_d_noindel,
#       AVG(isw_d_complex) AVG_d_complex,
#       COUNT(*) COUNT,
#       AVG(isw_d_indel) / AVG(isw_d_noindel)  `Di/Dn`
#FROM isw
{
    my $sql = ns();
    $sql->add_select( 'AVG(isw_distance)',  'AVG_distance' );
    $sql->add_select( 'AVG(isw_pi)',        'AVG_pi' );
    $sql->add_select( 'AVG(isw_d_indel)',   'AVG_d_indel' );
    $sql->add_select( 'AVG(isw_d_noindel)', 'AVG_d_noindel' );
    $sql->add_select( 'AVG(isw_d_complex)', 'AVG_d_complex' );
    $sql->add_select( 'COUNT(*)',           'COUNT' );
    $sql->add_select( 'AVG(isw_d_indel) / AVG(isw_d_noindel)', '`Di/Dn`' );
    $sql->from( ['isw'] );
    $sql->add_where( 'isw_distance' => \'>= 0' );
    $sql->add_where( 'isw_d_indel'  => \'IS NOT NULL' );

    $sql_file->set( 'three-distance_avg-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT
#  AVG(isw.isw_distance) AVG_distance,
#  AVG(isw.isw_pi) AVG_pi,
#  AVG(isw.isw_d_indel) AVG_d_indel,
#  AVG(isw.isw_d_noindel) AVG_d_noindel,
#  AVG(isw.isw_d_complex) AVG_d_complex,
#  COUNT(*) COUNT,
#  AVG(isw.isw_d_indel) / AVG(isw.isw_d_noindel) `Di/Dn`
#FROM isw
#WHERE (isw.isw_distance >= 0)
#  AND (isw.isw_d_indel IS NOT NULL)
#  AND (isw.isw_coding >= ?)
{
    my $sql = ns();
    $sql->add_select( 'AVG(isw.isw_distance)',  'AVG_distance' );
    $sql->add_select( 'AVG(isw.isw_pi)',        'AVG_pi' );
    $sql->add_select( 'AVG(isw.isw_d_indel)',   'AVG_d_indel' );
    $sql->add_select( 'AVG(isw.isw_d_noindel)', 'AVG_d_noindel' );
    $sql->add_select( 'AVG(isw.isw_d_complex)', 'AVG_d_complex' );
    $sql->add_select( 'COUNT(*)',               'COUNT' );
    $sql->add_select( 'AVG(isw.isw_d_indel) / AVG(isw.isw_d_noindel)',
        '`Di/Dn`' );

    $sql->from( ['isw'] );
    $sql->add_where( 'isw.isw_distance' => \'>= 0' );
    $sql->add_where( 'isw.isw_d_indel'  => \'IS NOT NULL' );
    $sql->add_where( 'isw.isw_coding'   => { op => '>=', value => '1' } );
    $sql->add_where( 'isw.isw_coding'   => { op => '<=', value => '1' } );

    $sql_file->set( 'three-distance_coding-2', $sql );
    print $sql->as_sql if $verbose;
}

#----------------------------------------------------------#
# multi_stat_factory.pl SQL
#----------------------------------------------------------#

#SELECT isw_distance distance,
#       AVG(isw_pi) AVG_D,
#       AVG(isw_d_indel) AVG_Di,
#       AVG(isw_d_noindel) AVG_Dni,
#       AVG(isw_d_bii)/2 `AVG_Dbii/2`,
#       AVG(isw_d_bnn)/2 `AVG_Dbnn/2`,
#       AVG(isw_d_complex) AVG_Dc,
#       AVG(isw_d_indel)/AVG(isw_d_noindel) `Di/Dn`,
#       COUNT(*) COUNT
#FROM isw s, indel i
#WHERE s.isw_indel_id = i.indel_id
#AND i.indel_slippage = 0
#GROUP BY isw_distance
{
    my $sql = ns();
    $sql->add_select( 'isw_distance',                          'distance' );
    $sql->add_select( 'AVG(isw_pi)',                           'AVG_D' );
    $sql->add_select( 'AVG(isw_d_indel)',                      'AVG_Di' );
    $sql->add_select( 'AVG(isw_d_noindel)',                    'AVG_Dni' );
    $sql->add_select( 'AVG(isw_d_bii)/2',                      '`AVG_Dbii/2`' );
    $sql->add_select( 'AVG(isw_d_bnn)/2',                      '`AVG_Dbnn/2`' );
    $sql->add_select( 'AVG(isw_d_complex)',                    'AVG_Dc' );
    $sql->add_select( 'AVG(isw_d_indel) / AVG(isw_d_noindel)', '`Di/Dn`' );
    $sql->add_select( 'COUNT(*)',                              'COUNT' );

    $sql->add_join(
        isw => {
            type      => 'inner',
            table     => 'indel',
            condition => 'isw.isw_indel_id = indel.indel_id',
        }
    );
    $sql->add_where( 'indel.indel_slippage' => \'= 0' );

    $sql->group( { column => 'isw_distance' } );

    $sql_file->set( 'multi-distance-0', $sql );
    print $sql->as_sql if $verbose;
}

{
    my $sql = ns();
    $sql->add_select( 'isw_distance',        'distance' );
    $sql->add_select( 'AVG(isw_pi)',         'AVG_D' );
    $sql->add_select( 'AVG(isw_d_indel2)',   'AVG_Di2' );
    $sql->add_select( 'AVG(isw_d_noindel2)', 'AVG_Dni2' );
    $sql->add_select( 'AVG(isw_d_bii2)/2',   '`AVG_Dbii2/2`' );
    $sql->add_select( 'AVG(isw_d_bnn2)/2',   '`AVG_Dbnn2/2`' );
    $sql->add_select( 'AVG(isw_d_complex2)', 'AVG_Dc2' );
    $sql->add_select( 'AVG(isw_d_indel2) / AVG(isw_d_noindel2)', '`Di2/Dn2`' );
    $sql->add_select( 'COUNT(*)',                                'COUNT' );

    $sql->add_join(
        isw => {
            type      => 'inner',
            table     => 'indel',
            condition => 'isw.isw_indel_id = indel.indel_id',
        }
    );
    $sql->add_where( 'indel.indel_slippage' => \'= 0' );

    $sql->group( { column => 'isw_distance' } );

    $sql_file->set( 'multi-distance2-0', $sql );
    print $sql->as_sql if $verbose;
}

{
    my $sql = ns();
    $sql->add_select( 'isw_distance',        'distance' );
    $sql->add_select( 'AVG(isw_pi)',         'AVG_D' );
    $sql->add_select( 'AVG(isw_d_indel3)',   'AVG_Di3' );
    $sql->add_select( 'AVG(isw_d_noindel3)', 'AVG_Dni3' );
    $sql->add_select( 'AVG(isw_d_bii3)/2',   '`AVG_Dbii3/2`' );
    $sql->add_select( 'AVG(isw_d_bnn3)/2',   '`AVG_Dbnn3/2`' );
    $sql->add_select( 'AVG(isw_d_complex3)', 'AVG_Dc3' );
    $sql->add_select( 'AVG(isw_d_indel3) / AVG(isw_d_noindel3)', '`Di3/Dn3`' );
    $sql->add_select( 'COUNT(*)',                                'COUNT' );

    $sql->add_join(
        isw => {
            type      => 'inner',
            table     => 'indel',
            condition => 'isw.isw_indel_id = indel.indel_id',
        }
    );
    $sql->add_where( 'indel.indel_slippage' => \'= 0' );

    $sql->group( { column => 'isw_distance' } );

    $sql_file->set( 'multi-distance3-0', $sql );
    print $sql->as_sql if $verbose;
}

#SELECT  indel_length,
#        COUNT(*) indel_number,
#        AVG(indel_gc) AVG_gc,
#        SUM(indel_length) indel_sum
#FROM indel
#WHERE indel.indel_slippage = 0
#GROUP BY indel_length
{
    my $sql = ns();
    $sql->add_select('indel_length');
    $sql->add_select( 'COUNT(*)',          'indel_number' );
    $sql->add_select( 'AVG(indel_gc)',     'AVG_gc' );
    $sql->add_select( 'SUM(indel_length)', 'indel_sum' );
    $sql->from( ['indel'] );
    $sql->add_where( 'indel.indel_slippage' => \'= 0' );
    $sql->group( { column => 'indel_length' } );

    $sql_file->set( 'multi-indel_length-0', $sql );
    print $sql->as_sql if $verbose;
}

#----------------------------------------------------------#
# ld_stat_factory.pl SQL
#----------------------------------------------------------#

#SELECT
#  isw.isw_distance distance,
#  AVG(snp.snp_r) AVG_r,
#  AVG(POWER(snp.snp_r, 2)) AVG_r2,
#  AVG(snp.snp_dprime) AVG_Dprime,
#  AVG(ABS(snp.snp_dprime)) AVG_Dprime_abs,
#  COUNT(*) COUNT
#FROM isw
#  INNER JOIN indel ON
#    isw.isw_indel_id = indel.indel_id
#  INNER JOIN snp ON
#    isw.isw_id = snp.isw_id
#WHERE (indel.indel_occured != 'unknown')
#  AND (snp.snp_occured != 'unknown')
#GROUP BY
#  isw.isw_distance
{
    my $name = 'ld-indel_ld-0';

    my $sql = ns();
    $sql->add_select( 'isw.isw_distance',         'distance' );
    $sql->add_select( 'AVG(snp.snp_r)',           'AVG_r' );
    $sql->add_select( 'AVG(POWER(snp.snp_r, 2))', 'AVG_r2' );
    $sql->add_select( 'AVG(snp.snp_dprime)',      'AVG_Dprime' );
    $sql->add_select( 'AVG(ABS(snp.snp_dprime))', 'AVG_Dprime_abs' );
    $sql->add_select( 'COUNT(*)',                 'COUNT' );

    $sql->add_join(
        isw => [
            {   type      => 'inner',
                table     => 'indel',
                condition => 'isw.isw_indel_id = indel.indel_id',
            },
            {   type      => 'inner',
                table     => 'snp',
                condition => 'isw.isw_id = snp.isw_id',
            },
        ]
    );
    $sql->add_where( 'indel.indel_occured' => \"!= 'unknown'" );
    $sql->add_where( 'snp.snp_occured'     => \"!= 'unknown'" );
    $sql->group( { column => 'isw.isw_distance' } );

    $sql_file->set( $name, $sql );

    print "\n[$name]\n";
    print $sql->as_sql if $verbose;
}

#SELECT
#  isw.isw_distance distance,
#  AVG(POWER(snp.snp_r, 2)) AVG_r2,
#  AVG(POWER(snp.snp_r_s, 2)) AVG_r2_s,
#  AVG(ABS(snp.snp_dprime)) AVG_Dprime_abs,
#  AVG(ABS(snp.snp_dprime_s)) AVG_Dprime_abs_s,
#  COUNT(*) COUNT
#FROM isw
#  INNER JOIN indel ON
#    isw.isw_indel_id = indel.indel_id
#  INNER JOIN snp ON
#    isw.isw_id = snp.isw_id
#WHERE (indel.indel_occured != 'unknown')
#  AND (snp.snp_occured != 'unknown')
#GROUP BY
#  isw.isw_distance
{
    my $name = 'ld-snp_ld-0';

    my $sql = ns();
    $sql->add_select( 'isw.isw_distance',           'distance' );
    $sql->add_select( 'AVG(POWER(snp.snp_r, 2))',   'AVG_r2' );
    $sql->add_select( 'AVG(POWER(snp.snp_r_s, 2))', 'AVG_r2_s' );
    $sql->add_select( 'AVG(ABS(snp.snp_dprime))',   'AVG_Dprime_abs' );
    $sql->add_select( 'AVG(ABS(snp.snp_dprime_s))', 'AVG_Dprime_abs_s' );
    $sql->add_select( 'COUNT(*)',                   'COUNT' );

    $sql->add_join(
        isw => [
            {   type      => 'inner',
                table     => 'indel',
                condition => 'isw.isw_indel_id = indel.indel_id',
            },
            {   type      => 'inner',
                table     => 'snp',
                condition => 'isw.isw_id = snp.isw_id',
            },
        ]
    );
    $sql->add_where( 'indel.indel_occured' => \"!= 'unknown'" );
    $sql->add_where( 'snp.snp_occured'     => \"!= 'unknown'" );
    $sql->group( { column => 'isw.isw_distance' } );

    $sql_file->set( $name, $sql );

    print "\n[$name]\n";
    print $sql->as_sql if $verbose;
}

#SELECT
#  isw.isw_distance distance,
#  AVG(POWER(snp.snp_r, 2)) AVG_r2,
#  AVG(snp.snp_r2_s) AVG_r2_s,
#  AVG(ABS(snp.snp_dprime)) AVG_Dprime_abs,
#  AVG(snp.snp_dprime_abs_s) AVG_Dprime_abs_s,
#  AVG(snp.snp_r2_i) AVG_r2_i,
#  AVG(snp.snp_r2_ni) AVG_r2_ni,
#  AVG(snp.snp_dprime_abs_i) AVG_Dprime_abs_i,
#  AVG(snp.snp_dprime_abs_ni) AVG_Dprime_abs_ni,
#  COUNT(*) COUNT
#FROM isw
#  INNER JOIN indel ON
#    isw.isw_indel_id = indel.indel_id
#  INNER JOIN snp ON
#    isw.isw_id = snp.isw_id
#WHERE (indel.indel_occured != 'unknown')
#  AND (snp.snp_occured != 'unknown')
#GROUP BY
#  isw.isw_distance
{
    my $name = 'ld-snps_ld-0';

    my $sql = ns();
    $sql->add_select( 'isw.isw_distance',           'distance' );
    $sql->add_select( 'AVG(POWER(snp.snp_r, 2))',   'AVG_r2' );
    $sql->add_select( 'AVG(snp.snp_r2_s)',          'AVG_r2_s' );
    $sql->add_select( 'AVG(ABS(snp.snp_dprime))',   'AVG_Dprime_abs' );
    $sql->add_select( 'AVG(snp.snp_dprime_abs_s)',  'AVG_Dprime_abs_s' );
    $sql->add_select( 'AVG(snp.snp_r2_i)',          'AVG_r2_i' );
    $sql->add_select( 'AVG(snp.snp_r2_ni)',         'AVG_r2_ni' );
    $sql->add_select( 'AVG(snp.snp_dprime_abs_i)',  'AVG_Dprime_abs_i' );
    $sql->add_select( 'AVG(snp.snp_dprime_abs_ni)', 'AVG_Dprime_abs_ni' );
    $sql->add_select( 'COUNT(*)',                   'COUNT' );

    $sql->add_join(
        isw => [
            {   type      => 'inner',
                table     => 'indel',
                condition => 'isw.isw_indel_id = indel.indel_id',
            },
            {   type      => 'inner',
                table     => 'snp',
                condition => 'isw.isw_id = snp.isw_id',
            },
        ]
    );
    $sql->add_where( 'indel.indel_occured' => \"!= 'unknown'" );
    $sql->add_where( 'snp.snp_occured'     => \"!= 'unknown'" );
    $sql->group( { column => 'isw.isw_distance' } );

    $sql_file->set( $name, $sql );

    print "\n[$name]\n";
    print $sql->as_sql if $verbose;
}

END {
    $sql_file->write;
}

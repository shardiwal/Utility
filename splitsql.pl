#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use File::Slurp;
use File::Basename;
use File::Path;
use Getopt::Std;

my %opts;
my $valid_option = getopts( 'hvfd:o:st:c:', \%opts );

sub usage {
    my $me = basename(__FILE__);
    print "USAGE
        $me [-h] [-v] [-d <db_name>] [-o <out.sql>] [-s] [-t <table>] [-c <text>] [in.sql]

DESCRIPTION

        Splits a mysqldump file into separate files by table names.
        Each table is further split into three files:

           \$table.sql       - Table creation
           \$table.data.sql  - Table data
           \$table.aux.N.sql - For storing triggers associated the \$table.
                               'N' is a number for safeguarding against
                               accidental overwriting during the split.

ARGUMENTS

        in.sql         mysqldump file, if not given, read from stdin.

OPTIONS

        -v             Verbose output.
        -o <out.sql>   Name of main file where tables will be sourced,
                         default is 'genseq.sql'.
        -d <db_name>   The database name to be used, default is 'genseq'.
        -f             Force deletion of 'db_name_tables' directory.
                         If not specified ask for confirmation.
        -s             Dumps the tables structure only, leave
                         *.data.sql intact.
        -t             Dumps the given table only.
        -c <text>      Insert <text> at the top of the main file.
        -h             Show this help
";
}

if ( defined $opts{h} ) {
    usage();
    exit 0;
}

my $verbose = 0;
if ( defined $opts{v} ) {
    $verbose = 1;
}
my $out           = $opts{o} || 'database.sql';
my $database_name = $opts{d} || 'database_name';

my $structure_only = 0;
if ( defined $opts{s} ) {
    $structure_only = 1;
}

my $table = $opts{t} || '';

my $preamble_text = $opts{c};

my $directory = '/var/www/' . $database_name . '_tables';

if ( -f $directory ) {
    die "ERROR: '$directory' exists and it is not a directory\n";
}

my %files_to_delete;
if ( -d $directory ) {
    my $answer;
    if ( defined $opts{f} ) {
        $answer = 'y';
    }
    else {
        print
"Content of directory $directory will be deleted, ok to continue? (y/n): ";
        my $answer = <STDIN>;
        chomp $answer;
    }
    if ( $answer eq 'y' ) {
        while ( my $file = <$directory/$table*.sql> ) {
            $files_to_delete{$file} = 1;
        }
    }
    else {
        print "Aborting ...\n";
        exit 0;
    }
}

if ( !-d $directory ) {
    mkdir $directory || die "ERROR: Could not create directory $directory: $!";
}

sub verbose {
    if ( !$verbose ) {
        return;
    }
    my ( $text, $no_newline ) = @_;
    print $text;
    if ( !defined $no_newline ) {
        print "\n";
    }
}

sub do_not_delete {
    my ( $file_name ) = @_;
    $files_to_delete{$file_name} = 0;
}

sub add_to_main_file {
    my ( $file_name, $append ) = @_;
    do_not_delete($file_name);
    if ( !defined $append ) {
        $append = 1;
    }
    my $table_dir = $database_name . '_tables';
    $file_name =~ s{.*/($table_dir/)}{$1};
    write_file( $out, { append => $append }, "source $file_name\n" );
    verbose("$file_name");
}

sub get_sub_filename_for {
    my ( $basename ) = @_;
    return "$directory/$basename.sql";
}

my $append_to_main_file = 0;
if ( defined $preamble_text ) {
    $append_to_main_file = 1;
    write_file( $out, { append => 0 }, "$preamble_text\n" );
}

my $file_name = get_sub_filename_for('head');

# Truncate head.sql
write_file( $file_name, { append => 0 }, "-- \n" );

verbose("$out");
add_to_main_file( $file_name, $append_to_main_file );
my @lines;
if ( defined $ARGV[0] ) {
    @lines = read_file( $ARGV[0] );
}
else {
    @lines = <STDIN>;
}

my @aux_sql;
my %aux_count_for;
my $table_name;
my $current_table_name = '';
my %n_INSERT_INTO_lines_for;
foreach my $line (@lines) {
    if ( $line =~ /^--$/ ) {

        # Ignoring this is good for normalization between
        # "dump" and "dump -s" (structure only)
        next;
    }
    if ( $file_name eq "$directory/head.sql" ) {
        if (   $line =~ /^-- MySQL dump/
            || $line =~ /^-- Host:/
            || $line =~ /^-- Server version/
            || $line =~ /^-- Current Database: `([^`]+)`/
            || $line =~ /^CREATE DATABASE .*`([^`]+)`/
            || $line =~ /^USE `([^`]+)`/ )
        {
            next;
        }
    }
    if ( $line =~ /^-- Table structure for table `([^`]+)`/ ) {
        $table_name = $1;
        print "Table $table_name \n";
        $file_name = get_sub_filename_for($1);
        add_to_main_file($file_name);
        write_file( $file_name, { append => 0 }, $line );
        if ($structure_only) {

            # When -s (structure only) is given,
            # preserve existing *.data.sql
            my $data_file = get_sub_filename_for( $1 . '.data' );
            add_to_main_file($data_file);
        }
        next;
    }
    if ( $line =~ /^-- Dumping data for table `([^`]+)`/ ) {
        $current_table_name = $1;
        $file_name          = get_sub_filename_for( $1 . '.data' );
        add_to_main_file($file_name);
        if ( !$structure_only ) {
            write_file( $file_name, { append => 0 }, $line );
        }
        next;
    }
    if ( $line =~ /^\/\*![0-9]+ SET \@SAVE_SQL_MODE.*/ ) {
        $aux_count_for{$table_name} += 1;
        $file_name = get_sub_filename_for(
            $table_name . '.aux.' . $aux_count_for{$table_name} );
        add_to_main_file($file_name);
        write_file( $file_name, { append => 0 }, $line );
        next;
    }
    if ( $line =~ /^-- Dumping routines for database/ ) {
        $line      = "-- Dumping routines for database\n";
        $file_name = get_sub_filename_for('tail');
        add_to_main_file($file_name);
        write_file( $file_name, { append => 0 }, $line );
        next;
    }
    if ( $line =~ /^-- Dump completed on / ) {
        next;
    }
    if ( $file_name !~ /data\.sql$/ ) {
        write_file( $file_name, { append => 1 }, $line );
    }
    elsif ( $structure_only == 0 ) {

        # TODO make 10000 chunk size configurable from command line
        my $append = 1;
        if ( $line =~ /^INSERT INTO/ ) {
            $n_INSERT_INTO_lines_for{$current_table_name} += 1;
            if ( $n_INSERT_INTO_lines_for{$current_table_name} % 10000 == 0 ) {

              # Ensure there's a new line at the end so that reformat_inserts.pl
              # prints the ending ';'
                write_file( $file_name, { append => 1 }, "\n" );
                my $sequence = sprintf( "%010s",
                    $n_INSERT_INTO_lines_for{$current_table_name} );
                $file_name = get_sub_filename_for(
                    $current_table_name . '.' . $sequence . '.data' );
                add_to_main_file($file_name);
                $append = 0;
            }
        }
        write_file( $file_name, { append => $append }, $line );
    }
}

foreach my $filename ( keys %files_to_delete ) {
    if ( $files_to_delete{$filename} == 1 ) {
        if ( -f $filename ) {
            unlink $filename;
        }
    }
}

verbose("File '$out' and directory '$directory' updated.");

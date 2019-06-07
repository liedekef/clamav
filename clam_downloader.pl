#!/usr/bin/perl
#
# File name: clamdownloader.pl
#
#############################################################################
#
use strict;
use warnings;

use Net::DNS;
use File::Copy;

# full path to clamd basedir
my $clamdb="/var/www/html/";
if (! -d $clamdb) {
   mkdir("$clamdb");
}

# mirror where files such as daily-12133.cdiff exist
my $mirror="http://database.clamav.net";

# get the TXT record for current.cvd.clamav.net
my $txt = getTXT("current.cvd.clamav.net");

exit unless $txt;

chdir($clamdb) || die ("Can't chdir to $clamdb : $!\n");

# temp dir for wget updates
mkdir("$clamdb/temp");

# get what we need
my ( $clamv, $mainv , $dailyv, $x, $y, $z, $safebrowsingv, $bytecodev ) = split /:/, $txt ;

#print "FIELDS main=$mainv daily=$dailyv bytecode=$bytecodev\n";

updateFile('main',$mainv);
updateFile('daily',$dailyv);
updateFile('bytecode',$bytecodev);

# remove old cdiff files
unlink grep { -f and -M >= 10 } glob "$clamdb/*cdiff";

sub getTXT {
        use Net::DNS;
        my $domain = shift @_;
        my $rr;
        my $res = Net::DNS::Resolver->new;
        my $txt_query = $res->query($domain,"TXT");
        if ($txt_query) {
                return ($txt_query->answer)[0]->txtdata;
        } else {
                warn "Unable to get TXT Record : ", $res->errorstring, "\n";
                return 0;
        }
}

sub getSigVersion {
        my $file=shift @_;
        my $cmd="sigtool -i $file";
        open P, "$cmd |" || die("Can't run $cmd : $!");
        while (<P>) {
                next unless /Version: (\d+)/;
                return $1;
        }
        close(P);
        return -1;
}
sub updateFile {
        my $file=shift @_;
        my $currentversion=shift @_;
        my $old=0;
        my $downloadfull=0;

        if  ( ! -e "$clamdb/$file.cvd" ) {
                warn "file $file.cvd does not exist, skipping cdiffs\n";
                # mark that we want to download a new full version
                $downloadfull=1;
        } elsif  ( ! -z "$clamdb/$file.cvd" ) {
                $old = getSigVersion("$clamdb/$file.cvd");
                if ( $old > 0) {
                        if ($old<$currentversion) {
                            print "$file old: $old current: $currentversion\n";
                            # mirror all the diffs
                            for (my $count = $old + 1 ; $count <= $currentversion; $count++) {
                                system("wget --no-cache -q -nH -nd -N -nv $mirror/$file-$count.cdiff");
                            }
                            # mark that we want to download a new full version
                            $downloadfull=1;
                        } else {
                            warn "file $file.cvd version up to date\n";
                            return;
                        }
                } else {
                        warn "file $file.cvd version unknown, skipping cdiffs\n";
                }
        } else {
                warn "file $file.cvd is zero, skipping cdiffs\n";
                # mark that we want to download a new full version
                $downloadfull=1;
        }
        
        if ($downloadfull) {
                # update the full file using a copy, then move back
                if (-e "$clamdb/$file.cvd" ) {
                        copy("$clamdb/$file.cvd","$clamdb/temp/$file.cvd");
                        #system("cp -a $clamdb/$file.cvd $clamdb/temp/$file.cvd");
                }
                system("cd $clamdb/temp;wget --no-cache -q -nH -nd -N -nv $mirror/$file.cvd");
                if  ( -e "$clamdb/temp/$file.cvd" && ! -z "$clamdb/temp/$file.cvd" ) {
                        if ( ! -e "$clamdb/$file.cvd") {
                                print "File temp/$file.cvd exists but not $file.cvd, moving temp/$file.cvd to $file.cvd\n";
                                move("$clamdb/temp/$file.cvd","$clamdb/$file.cvd");
                        } elsif ( getSigVersion("$clamdb/temp/$file.cvd") > getSigVersion("$clamdb/$file.cvd") ) {
                                print "File temp/$file.cvd is newer than $file.cvd, replacing $file.cvd with temp/$file.cvd\n";
                                move("$clamdb/temp/$file.cvd","$clamdb/$file.cvd");
                        } else {
                                print "Not using file temp/$file.cvd\n";
                                unlink("$clamdb/temp/$file.cvd");
                        }
                } else {
                        warn "File temp/$file.cvd is not valid, not copying back !\n";
                        unlink("$clamdb/temp/$file.cvd");
                }
                system("chmod 644 $clamdb/*.cvd $clamdb/*.cdiff" );
        }
}
__END__

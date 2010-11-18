package MagicList::Singleton;

use strict;
use warnings;

use Carp qw/ croak /;

our (@a, %h, $p);
@a = ();
%h = ();
$p = 0;

sub TIEARRAY {
    my $class = shift;
    my $what = 'a';
    return bless \$what, $class;
}

sub TIEHASH {
    my $class = shift;
    if (@_ and $_[-1] eq 'autovivify') {
        no warnings qw/ redefine /;
        *_fetch_hash = \&_fetch_hash_autovivify;
    }
    my $what = 'h';
    return bless \$what, $class;
}

sub FETCH {
    my $what = ${shift()};
    if ($what eq 'a') {
        goto &_fetch_array;
    } elsif ($what eq 'h') {
        goto &_fetch_hash;
    }
}

sub STORE {
    my $what = ${shift()};
    if ($what eq 'a') {
        goto &_store_array;
    } elsif ($what eq 'h') {
        goto &_store_hash;
    }
}

sub CLEAR {
    # same thing for array and hash;
    @a = ();
    %h = ();
    $p = 0;
    return;
}

## array-specific

sub _fetch_array {
    my $i = shift;
    return undef if $i > @a;
    return $a[$i];
}

sub _store_array {
    my $i = shift;
    my $d = shift;
    croak "Item already in list!" if exists $h{$d};
    if (defined $a[$i]) {
        croak "Index mismatch!" if $i != delete $h{$a[$i]};
    }
    $h{$d} = $i;
    return $a[$i] = $d;
}

sub FETCHSIZE {
    return scalar @a;
}

sub STORESIZE {
}

sub PUSH {
    shift;
    my @list = grep { not exists $h{$_} } @_;
    my $i = scalar @a;
    $h{$_} = $i++ foreach @list;
    return push @a, @list;
}

sub POP {
    delete $h{$a[-1]};
    return pop @a;
}

sub SHIFT {
    delete $h{$a[0]};
    foreach (values %h) {
        --$_;
    }
    return shift @a;
}

sub UNSHIFT {
    shift;
    my @list = grep { not exists $h{$_} } @_;
    my $length = scalar @list;
    foreach (values %h) {
        $_ += $length;
    }
    my $i = 0;
    $h{$_} = $i++ foreach @list;
    return unshift @a, @list;
}

sub SPLICE {
    shift;
    my $offset = @_ ? shift : 0;
    my $length = @_ ? shift : scalar @a - $offset;
    my @list = grep { not exists $h{$_} } @_;
    my $s = scalar @list - $length;
    foreach (@a[($offset + $length)..$#a]) {
        $h{$_} += $s;
    }
    my $i = $offset;
    foreach (@list) {
        $h{$_} = $i++;
    }
    my @spliced = splice @a, $offset, $length, @list;
    delete $h{$_} foreach @spliced;
    return @spliced;
}

sub EXTEND {
}

## hash-specific

sub _fetch_hash {
    return $h{shift()};
}

sub _fetch_hash_autovivify {
    my $key = shift;
    return $h{$key} if exists $h{$key};
    push @a, $key;
    return $h{$key} = $#a;
}

sub _store_hash {
    my $key = shift;
    my $value = shift;

    ## if this flag is set, $key is not in the list yet
    my $add_flag = 1 - exists $h{$key};

    if ($value < 0) {
        $value += $add_flag + scalar @a;
    }

    croak "Index out of range!"
        if $value < 0
        or $value >= $add_flag + scalar @a;

    ## if not on the list yet, tack it on the end for now (might get moved later)
    if ($add_flag) {
        $h{$key} = scalar @a;
        push @a, $key;
    }

    my $current = $h{$key};
    return $value if $value == $current;
    if ($current < $value) {
        foreach (@a[($current + 1)..$value]) {
            --$h{$_};
        }
    }
    elsif ($current > $value) {
        foreach (@a[$value..($current - 1)]) {
            ++$h{$_};
        }
    }
    splice(@a, $value, 0, splice(@a, $current, 1));
    return $h{$key} = $value;
}

sub DELETE {
    shift;
    my $i = delete $h{shift()};
    splice(@a, $i, 1);
    foreach (@a[$i..$#a]) {
        --$h{$_};
    }
    return $i;
}

sub EXISTS {
    shift;
    return exists $h{shift()};
}

sub FIRSTKEY {
    $p = 0;
    return $a[0];
}

sub NEXTKEY {
    ++$p;
    if ($p == scalar @a) {
        $p = 0;
        return;
    }
    return $a[$p];
}

sub SCALAR {
    return scalar %h;
}

# must not forget this line
1;

__END__

=head1 NAME

MagicList::Singleton -- a list of unique elements that maintains a
cross-reference table

=head1 DESCRIPTION

Sometimes you want to store a list in an array, but you also want the
ability, given an arbitrary list element, to easily find its index in
the array, without having to scan the array.  You can use a hash to
keep track, but then every time you update the array, you have to
update the hash.

Or do you?

=head1 USAGE

 tie @a, 'MagicList::Singleton';       # the list
 tie %h, 'MagicList::Singleton';       # the cross-reference table

 # create the list
 @a = qw/ perl python pascal prolog /;
 print "@a";                           # perl python pascal prolog
 # check the cross-references
 print $h{perl};                       # 0
 print $h{prolog};                     # 3

 # add an element
 push @a, qw/ php /;
 print "@a";                           # perl python pascal prolog php
 print $h{php};                        # 4

 # try to add an element already there
 push @a, qw/ perl /;
 print "@a";                           # perl python pascal prolog php

 @a = sort @a;
 print "@a";                           # pascal perl php prolog python
 # check the cross-references
 print $h{perl};                       # 1
 print $h{prolog};                     # 3

 # restore order to the universe
 $h{perl} = 0;                         # put perl first
 $h{php} = -1;                         # put php last
 print "@a";                           # perl pascal prolog python php

 # an interloper
 splice @a, 2, 0, qw/ ruby /;
 print "@a";                           # perl pascal ruby prolog python php
 # check the cross-references
 print $h{python};                     # 4
 # remove the interloper
 splice @a, 2, 1;
 print "@a";                           # perl pascal prolog python php
 # check the cross-references
 print $h{python};                     # 3

 # the interloper returns
 $h{ruby} = 2;                         # put ruby at index 2
 print "@a";                           # perl pascal ruby prolog python php
 # check the cross-references
 print $h{python};                     # 4
 # remove the interloper
 splice @a, 2, 1;
 print "@a";                           # perl pascal prolog python php

 # the interloper tries to hide
 $h{ruby} = int(4 * rand);             # ruby is somewhere among first 4
 # check the cross-references
 print $h{php};                        # 5
 # we don't know the index,
 # so we delete by name!
 delete $h{ruby};
 print "@a";                           # perl pascal prolog python php
 print $h{php};                        # 4

 # an alternative usage
 tie @a, 'MagicList::Singleton';               # the list
 tie %h, 'MagicList::Singleton', 'autovivify'; # the cross-reference table

 # create the list
 @a = qw/ perl python pascal prolog /;
 # ask for the index of an item not on the list
 print $h{php};                                # 4
 # the item autovivifies by being appended
 # to check:
 print "@a";                                   # perl python pascal prolog php

=head1 COPYRIGHT AND LICENSE

Copyright Theron Stanford E<lt>shixilun@gmail.comE<gt>

Perl Artistic License

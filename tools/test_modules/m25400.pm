#!/usr/bin/env perl

##
## Author......: See docs/credits.txt
## License.....: MIT
##

# based off m10500 but added the owner password part ($o) to be able to test the edit password
# two TODOs still (now only works if no user password is set):
# 1. TODO use user password as input for md5 of o_digest if no owner password is set
# 2. TODO dynamically add user password including padding to the RC4 input for the computation of the pdf o-value

# easy test shortcut for debugging
# a=$(echo 1 | tools/test.pl passthrough 10500 | tail -n1); echo $a; echo 1 | ./hashcat --potfile-disable --runtime 400 --hwmon-disable -O -D 2 --backend-vector-width 4 -a 0 -m 10500 $a

use strict;
use warnings;

use Crypt::RC4;
use Digest::MD5 qw (md5);

my $PDF_PADDING =
[
  0x28, 0xbf, 0x4e, 0x5e, 0x4e, 0x75, 0x8a, 0x41, 0x64, 0x00, 0x4e, 0x56,
  0xff, 0xfa, 0x01, 0x08, 0x2e, 0x2e, 0x00, 0xb6, 0xd0, 0x68, 0x3e, 0x80,
  0x2f, 0x0c, 0xa9, 0xfe, 0x64, 0x53, 0x69, 0x7a
];

sub module_constraints { [[0, 15], [32, 32], [-1, -1], [-1, -1], [-1, -1]] }

sub pdf_compute_encryption_key_user
{
  my $word  = shift;
  my $padding   = shift;
  my $id        = shift;
  my $u         = shift;
  my $o         = shift;
  my $P         = shift;
  my $V         = shift;
  my $R         = shift;
  my $enc       = shift;

  ## start

  my $data;

  $data .= $word;

  $data .= substr ($padding, 0, 32 - length $word);

  $data .= pack ("H*", $o);
  $data .= pack ("I",  $P);
  $data .= pack ("H*", $id);

  if ($R >= 4)
  {
    if (!$enc)
    {
      $data .= pack ("I", -1);
    }
  }

  my $res = md5 ($data);

  if ($R >= 3)
  {
    for (my $i = 0; $i < 50; $i++)
    {
      $res = md5 ($res);
    }
  }

  return $res;
}


sub pdf_compute_encryption_key_owner
{
  my $word  = shift;
  my $padding   = shift;
  my $id        = shift;
  my $u         = shift;
  my $o         = shift;
  my $P         = shift;
  my $V         = shift;
  my $R         = shift;
  my $enc       = shift;

  # TODO use user password as input for md5 of o_digest if no owner password is set
  my $data;
  $data .= $word;
  $data .= substr ($padding, 0, 32 - length $word);
  my $o_digest = md5 ($data);

  if ($R >= 3)
  {
    for (my $i = 0; $i < 50; $i++)
    {
      $o_digest = md5 ($o_digest);
    }
  }

  #printf("\$o_digest = %s\n", unpack ("H*", $o_digest));


  my $o_key;
  if ($R == 2)
  {
    $o_key = substr($o_digest, 0, 8);  # rc4 key is always 5 for revision 2, but for 3 or greather is dependent on the value of the encryption dictionaries length entry
  }
  else
  {
  $o_key = substr($o_digest, 0, 16); #length is always 128 bits or 16 bytes
  }
  #printf("\$o_key = %s\n", unpack ("H*", $o_key));

  return $o_key;
}

sub module_generate_hash
{
  my $word = shift;
  my $id   = shift;
  my $u    = shift;
  my $o    = shift;
  my $P    = shift;
  my $V    = shift;
  my $R    = shift;
  my $enc  = shift;

  if (defined $u == 0)
  {
    $u = "0" x 64;
  }

  my $u_save = $u;

  if (defined $o == 0)
  {
    $o = "0" x 64;
  }

  my $o_save = $u;

  if (defined $R == 0)
  {
    $R = random_number (3, 4);
  }

  if (defined $V == 0)
  {
    $V = ($R == 3) ? 2 : 4;
  }

  if (defined $P == 0)
  {
    $P = ($R == 3) ? -4 : -1028;
  }

  if (defined $enc == 0)
  {
    $enc = ($R == 3) ? 1 : random_number (0, 1);
  }

  my $padding;

  for (my $i = 0; $i < 32; $i++)
  {
    $padding .= pack ("C", $PDF_PADDING->[$i]);
  }


  ################ USER PASSWORD #################
  my $res = pdf_compute_encryption_key_user($word, $padding, $id, $u, $o, $P, $V, $R, $enc);

  my $digest = md5 ($padding . pack ("H*", $id));

  my $m = Crypt::RC4->new ($res);
  $u = $m->RC4 ($digest);

  my @ress = split "", $res;

  #do xor of rc4 19 times
  for (my $x = 1; $x <= 19; $x++)
  {
    my @xor;

    for (my $i = 0; $i < 16; $i++)
    {
      $xor[$i] = chr (ord ($ress[$i]) ^ $x);
    }

    my $s = join ("", @xor);

    my $m2 = Crypt::RC4->new ($s);

    $u = $m2->RC4 ($u);
  }


  ################ OWNER PASSWORD #################
  my $o_key = pdf_compute_encryption_key_owner($word, $padding, $id, $u, $o, $P, $V, $R, $enc);
  my $n = Crypt::RC4->new ($o_key);
  $o = $n->RC4(substr ($padding, 0, 32 - length "")); # TODO dynamically add user password including padding to the RC4 input for the computation of the pdf o-value

  #printf("padding_empty_str = %s\n", unpack ("H*", substr ($padding, 0, 32 - length "")));

  my @ress2 = split "", $o_key;

  if ($R >= 3)
  {
    #do xor of rc4 19 times
    for (my $x = 1; $x <= 19; $x++)
    {
      my @xor;

      for (my $i = 0; $i < 16; $i++)
      {
        $xor[$i] = chr (ord ($ress2[$i]) ^ $x);
      }

      my $s = join ("", @xor);

      my $n2 = Crypt::RC4->new ($s);

      $o = $n2->RC4 ($o);
    }
  }

  #printf("\$u = %s\n", unpack ("H*", $u));

  $u .= substr (pack ("H*", $u_save), 16, 16);

  #printf("\$o = %s\n", unpack ("H*", $o));
  #printf("\$u = %s\n", unpack ("H*", $u));

  my $hash = sprintf ('$pdf$%d*%d*128*%d*%d*16*%s*32*%s*32*%s', $V, $R, $P, $enc, $id, unpack ("H*", $u), unpack ("H*", $o));

  return $hash;
}

sub module_verify_hash
{
  my $line = shift;

  my ($hash_in, $word) = split ":", $line;

  return unless defined $hash_in;
  return unless defined $word;

  my @data = split /\*/, $hash_in;

  return unless scalar @data == 11;

  my $V        = shift @data; $V = substr ($V, 5, 1);
  my $R        = shift @data;
  return unless (shift @data eq '128'); # length is always 128 here
  my $P        = shift @data;
  my $enc      = shift @data;
  return unless (shift @data eq '16');
  my $id       = shift @data;
  return unless (shift @data eq '32');
  my $u        = shift @data;
  return unless (shift @data eq '32');
  my $o        = shift @data;

  return unless defined $id;
  return unless defined $word;

  $word = pack_if_HEX_notation ($word);

  my $new_hash = module_generate_hash ($word, $id, $u, $o, $P, $V, $R, $enc);

  return ($new_hash, $word);
}

1;

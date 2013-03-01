#!/usr/bin/perl
# Copyright (C) 2007-2013  Alex Schroeder <alex@gnu.org>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

# This code started out as a fork of old-school-hex.pl.

use CGI qw/:standard/;
use CGI::Carp 'fatalsToBrowser';
use LWP::UserAgent;
use strict;

package Hex;

use Class::Struct;

struct Hex => {
	       x => '$',
	       y => '$',
	       type => '$',
	       label => '$',
	       map => 'Mapper',
	      };

sub str {
  my $self = shift;
  return '(' . $self->x . ',' . $self->y . ')';
}

my $dx = 100;
my $dy = 100*sqrt(3);

sub svg {
  my $self = shift;
  my $x = $self->x;
  my $y = $self->y;
  my $data = '';
  for my $type (@{$self->type}) {
    $data .= sprintf(qq{  <use x="%.1f" y="%.1f" xlink:href="#%s" />\n},
		     $x * $dx * 3/2, $y * $dy - $x%2 * $dy/2, $type);
  }
  $data .= sprintf(qq{  <text text-anchor="middle" x="%.1f" y="%.1f" %s>}
		   . qq{%02d.%02d}
		   . qq{</text>\n},
		   $x * $dx * 3/2, $y * $dy - $x%2 * $dy/2 - $dy * 0.4,
		   $self->map->text_attributes,
		   $x, $y);
  return $data;
}

sub svg_label {
  my $self = shift;
  my $x = $self->x;
  my $y = $self->y;
  my $data = sprintf(qq{  <text text-anchor="middle" x="%.1f" y="%.1f" %s %s>}
		   . $self->label
		   . qq{</text>\n},
		   $x * $dx * 3/2, $y * $dy - $x%2 * $dy/2 + $dy * 0.4,
		   $self->map->label_attributes,
		   $self->map->glow_attributes) if $self->label;
  $data .= sprintf(qq{  <text text-anchor="middle" x="%.1f" y="%.1f" %s>}
		   . $self->label
		   . qq{</text>\n},
		   $x * $dx * 3/2, $y * $dy - $x%2 * $dy/2 + $dy * 0.4,
		   $self->map->label_attributes) if $self->label;
  return $data;
}

package Mapper;

use Class::Struct;

struct Mapper => {
		  hexes => '@',
		  attributes => '%',
		  map => '$',
		  path => '%',
		  path_attributes => '%',
		  text_attributes => '$',
		  glow_attributes => '$',
		  label_attributes => '$',
		  messages => '@',
		  seen => '%',
		 };

my $example = q{
# map definition
0101 mountain
0102 mountain
0103 hill
0104 forest
0201 mountain
0202 hill
0203 coast
0204 empty
0301 mountain
0302 mountain
0303 plain
0304 sea
0401 hill
0402 sand house
0403 jungle "Harald's Repose"

include http://alexschroeder.ch/contrib/default.txt
};

sub example {
  return $example;
}

my $dx = 100;
my $dy = 100*sqrt(3);

sub initialize {
  my ($self, $map) = @_;
  $self->map($map);
  $self->process(split(/\r?\n/, $map));
}

sub process {
  my $self = shift;
  foreach (@_) {
    if (/^(\d\d)(\d\d)\s+([^"\r\n]+)?\s*(?:"(.+)")?/) {
      my $hex = Hex->new(x => $1, y => $2, map => $self);
      $hex->label($4);
      my @types = split(' ', $3);
      $hex->type(\@types);
      $self->add($hex);
    } elsif (/^(\S+)\s+attributes\s+(.*)/) {
      $self->attributes($1, $2);
    } elsif (/^(\S+)\s+path\s+attributes\s+(.*)/) {
      $self->path_attributes($1, $2);
    } elsif (/^(\S+)\s+path\s+(.*)/) {
      $self->path($1, $2);
    } elsif (/^text\s+(.*)/) {
      $self->text_attributes($1);
    } elsif (/^glow\s+(.*)/) {
      $self->glow_attributes($1);
    } elsif (/^label\s+(.*)/) {
      $self->label_attributes($1);
    } elsif (/^include\s+(\S*)/) {
      if (scalar keys %{$self->seen} > 5) {
	push(@{$self->messages}, "Includes are limited to five to prevent loops");
      } elsif ($self->seen($1)) {
	push(@{$self->messages}, "$1 was included twice");
      } else {
	$self->seen($1, 1);
	my $ua = LWP::UserAgent->new;
	my $response = $ua->get($1);
	if ($response->is_success) {
	  $self->process(split(/\n/, $response->decoded_content));
	} else {
	  push(@{$self->messages}, $response->status_line);
	}
      }
    }
  }
}

sub add {
  my ($self, $hex) = @_;
  push(@{$self->hexes}, $hex);
}

sub svg {
  my ($self) = @_;

  my ($minx, $miny, $maxx, $maxy);
  foreach my $hex (@{$self->hexes}) {
    $minx = $hex->x if not defined($minx);
    $maxx = $hex->x if not defined($maxx);
    $miny = $hex->y if not defined($miny);
    $maxy = $hex->x if not defined($maxy);
    $minx = $hex->x if $minx > $hex->x;
    $maxx = $hex->x if $maxx < $hex->x;
    $miny = $hex->y if $miny > $hex->y;
    $maxy = $hex->x if $maxy < $hex->y;
  }
  ($minx, $miny, $maxx, $maxy) =
    (($minx -0.5) * $dx - 10, ($miny - 1) * $dy - 10,
     ($maxx) * 1.5 * $dx + $dx + 10, ($maxy + 1.5) * $dy + 10);

  my $doc = qq{<?xml version="1.0" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" version="1.1"
     viewBox="$minx $miny $maxx $maxy"
     xmlns:xlink="http://www.w3.org/1999/xlink">
  <defs>};

  # collect hex types from attributess and paths in case the sets don't overlap
  my %type = ();
  foreach my $type (keys %{$self->attributes}) {
    $type{$type} = 1;
  }
  foreach my $type (keys %{$self->path}) {
    $type{$type} = 1;
  }

  # now go through them all
  foreach my $type (keys %type) {
    my $attributes = $self->attributes($type);
    my $path = $self->path($type);
    my $path_attributes = $self->path_attributes($type);
    my ($x1, $y1, $x2, $y2, $x3, $y3,
	$x4, $y4, $x5, $y5, $x6, $y6) =
	  (-$dx, 0, -$dx/2, $dy/2, $dx/2, $dy/2,
	   $dx, 0, $dx/2, -$dy/2, -$dx/2, -$dy/2);
    if ($path && $attributes) {
      $doc .= qq{
    <g id='$type'>
      <polygon $attributes points='$x1,$y1 $x2,$y2 $x3,$y3 $x4,$y4 $x5,$y5 $x6,$y6' />
      <path $path_attributes d='$path' />
    </g>};
    } elsif ($path) {
      $doc .= qq{
    <path id='$type' $path_attributes d='$path' />};
    } else {
      $doc .= qq{
    <polygon id='$type' $attributes points='$x1,$y1 $x2,$y2 $x3,$y3 $x4,$y4 $x5,$y5 $x6,$y6' />}
    }
  }
  $doc .= q{
  </defs>
};

  foreach my $hex (@{$self->hexes}) {
    $doc .= $hex->svg();
  }
  foreach my $hex (@{$self->hexes}) {
    $doc .= $hex->svg_label();
  }
  my $y = 10;
  foreach my $msg (@{$self->messages}) {
    $doc .= "  <text x='0' y='$y'>$msg</text>\n";
    $y += 10;
  }

  $doc .= "<!-- Source\n" . $self->map() . "\n-->";

  $doc .= qq{
</svg>};

  return $doc;
}

package main;

sub print_map {
  print header(-type=>'image/svg+xml');
  my $map = new Mapper;
  $map->initialize(shift);
  print $map->svg;
}

sub print_html {
  print (header(-type=>'text/html; charset=UTF-8'),
	 start_html(-encoding=>'UTF-8', -title=>'Text Mapper',
		    -author=>'kensanata@gmail.com'),
	 h1('Text Mapper'),
	 p('Submit your text desciption of the map.'),
	 start_form(-method=>'GET'),
	 p(textarea('map', Mapper::example(), 15, 60)),
	 p(submit()),
	 end_form(),
	 hr(),
	 p(a({-href=>'http://www.alexschroeder.ch/wiki/About'},
	     'Alex Schröder'),
	   a({-href=>url() . '/source'}, 'Source'),
	   a({-href=>'https://github.com/kensanata/hex-mapping'},
	     'GitHub')),
	 end_html());
}

sub main {
  if (param('map')) {
    print_map(param('map'));
  } elsif (path_info() eq '/source') {
    seek(DATA,0,0);
    undef $/;
    print <DATA>;
  } else {
    print_html();
  }
}

main ();

__DATA__

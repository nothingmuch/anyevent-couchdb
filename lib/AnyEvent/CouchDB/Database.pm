package AnyEvent::CouchDB::DB;

use strict;
use warnings;
use JSON::XS;
use AnyEvent::HTTP;
use Data::Dump::Streamer;
use URI::Escape;

# TODO - add error handling similar to what's in jquery.couch.js
# TODO - (but make it appropriate to perl)
our $cvcb = sub {
  my $cv = AnyEvent->condvar;
  my $cb = sub {
    my $data;
    eval {
      $data = decode_json($_[0]);
    };
    if ($@) {
      $cv->croak($@, $_[0], encode_json($_[1]));
    } else {
      $cv->send($data);
    }
  };
  ($cv, $cb);
};

# TODO - encode cgi params that couchdb expects
our $query = sub { "?" };

our $code_to_string = sub {
  ref($_[0])
    ? sprintf 'do { my $CODE1; %s; $CODE1 }',
      Data::Dump::Streamer->new->Data($_[0])->Out;
    : $_[0]
};

sub new {
  my ($class, $name, $uri) = @_;
  bless { name => $name, uri => $uri } => $class;
}

sub name {
  $_[0]->{name};
}

sub uri {
  $_[0]->{uri};
}

sub compact {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    POST    => ($self->uri . "_compact"),
    headers => { 'Content-Type' => 'application/json' },
    $cb
  );
  $cv;
}

sub create {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    PUT     => $self->uri,
    headers => { 'Content-Type' => 'application/json' },
    $cb
  );
  $cv;
}

sub drop {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    DELETE  => $self->uri,
    $cb
  );
  $cv;
}

sub info {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri, $cb);
  $cv;
}

sub all_docs {
  my ($self, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri."_all_docs".$query->($options), $cb);
  $cv;
}

sub open_doc {
  my ($self, $doc_id, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri.uri_escape($doc_id).$query->($options), $cb);
  $cv;
}

sub save_doc {
  my ($self, $doc, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  my ($method, $uri);
  if (defined $doc->{_id}) {
    $method = 'POST';
    $uri    = $self->uri;
  } else {
    $method = 'PUT';
    $uri    = $self->uri.uri_escape($doc->{_id});
  }
  http_request(
    $method => $uri.$query->($options),
    headers => { 'Content-Type' => 'application/json' },
    $cb
  );
  $cv;
}

sub remove_doc {
  my ($self, $doc, $options) = @_;
  die("Document is missing _id!") unless (defined $doc->{_id});
  my ($cv, $cb) = $cvcb->($options);
  http_request(
    DELETE  => $self->uri.uri_escape($doc->{_id}).$query->({ rev => $doc->{_rev} }),
    $cb
  );
  $cv;
}

sub query {
  my ($self, $map_fun, $reduce_fun, $language, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  $language ||= (ref($map_fun)) ? 'text/perl' : 'javascript';
  my $body = {
    language => $language,
    map      => $code_to_string->($map_fun),
  };
  if ($reduce_fun) {
    $body->{reduce} = $code_to_string->($reduce_fun);
  }
  http_request(
    POST    => $self->uri.'_temp_view'.$query->($options),
    headers => { 'Content-Type' => 'application/json' },
    body    => encode_json($body),
    $cb
  );
  $cv;
}

sub view {
  my ($self, $name, $options) = @_;
  my ($cv, $cb) = $cvcb->($options);
  http_get($self->uri."_view/".$name.$query->($options), $cb);
  $cv;
}

1;

__END__

=head1 NAME

AnyEvent::CouchDB::DB - an object representing a CouchDB database

=head1 SYNOPSIS

  use AnyEvent::CouchDB;
  use Data::Dump 'pp';

  my $couch = AnyEvent::CouchDB->new;
  my $db    = $couch->db('database');

  print pp($db->info->recv), "\n";
  my $cv = $db->save_doc({ just => 'give', me => 'a', hashref => { } });
  #
  # do other time-consuming operations
  #
  $cv->recv;  # when recv returns, the couchdb request finished

=head1 DESCRIPTION

Objects of this class represent a single CouchDB database.

=head1 API

=head2 General

=head3 new

=head3 name

=head3 uri

=head2 Database Level Operations

=head3 create

=head3 drop

=head3 info

=head3 compact

=head2 Document Level Operations

=head3 open_doc

=head3 save_doc

=head3 remove_doc

=head2 Database Queries

=head3 query

Ad-hoc query - give it an arbitrary map and reduce function

=head3 view

View query - use map/reduce functions that have been defined in design
documents

=head3 search

NOT IMPLEMENTED YET - It'll be a full-text search

=cut
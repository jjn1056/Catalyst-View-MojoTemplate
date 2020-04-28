package Catalyst::View::MojoTemplate;

use Moo;
use Mojo::Template;

extends 'Catalyst::View';

our $VERSION = 0.001;

has app => (is=>'ro');
has auto_escape => (is=>'ro', required=>1, default=>1);
has append => (is=>'ro', required=>1, default=>'');
has prepend => (is=>'ro', required=>1, default=>'');
has capture_end => (is=>'ro', required=>1, default=>sub {'end'});
has capture_start => (is=>'ro', required=>1, default=>sub {'begin'});
has comment_mark => (is=>'ro', required=>1, default=>'#');
has encoding => (is=>'ro', required=>1, default=>'UTF-8');
has escape_mark => (is=>'ro', required=>1, default=>'=');
has expression_mark => (is=>'ro', required=>1, default=>'=');
has line_start => (is=>'ro', required=>1, default=>'%');
has replace_mark => (is=>'ro', required=>1, default=>'%');
has trim_mark => (is=>'ro', required=>1, default=>'%');
has tag_start=> (is=>'ro', required=>1, default=>'<%');
has tag_end => (is=>'ro', required=>1, default=>'%>');
has ['name', 'namespace'] => (is=>'rw');
has content_type => (is=>'ro', required=>1, default=>sub { 'text/html' });
has template_extension => (is=>'ro', required=>1, default=>sub { '.mt' });
has helpers => (is=>'ro', predicate=>'has_helpers');

has _mojo_template => (
  is => 'ro',
  init_arg => undef,
  lazy => 1,
  builder => '_build_mojo_template',
);

  sub _build_mojo_template {
    my $self = shift;
    my %args = (
      auto_escape => $self->auto_escape,
      append => $self->append,
      capture_end => $self->capture_end,
      capture_start => $self->capture_start,
      comment_mark => $self->comment_mark,
      encoding => $self->encoding,
      escape_mark => $self->escape_mark,
      expression_mark => $self->expression_mark,
      line_start => $self->line_start,
      prepend => $self->prepend,
      trim_mark => $self->trim_mark,
      tag_start => $self->tag_start,
      tag_end => $self->tag_end,
      vars => 1,
    );
    return Mojo::Template->new(%args);
  }


has path_base => (
  is=>'ro',
  required=>1,
  lazy=>1,
  builder=>'_build_path_base');
 
  sub _build_path_base {
    my $self = shift;
    my $root = $self->app->path_to('root');
    die "No directory '$root'" unless -e $root;

    return $root;
  }

sub COMPONENT {
  my ($class, $app, $args) = @_;
  $args = $class->merge_config_hashes($class->config, $args);
  $args->{app} = $app;

  return $class->new($app, $args);
}

sub process {
  my ($self, $c) = @_;

  my $template = $self->find_template($c); 
  my %template_args = $self->template_vars($c);
  my $output = $self->render($c, $template, \%template_args);

  $c->response->content_type($self->content_type) unless $c->response->content_type;
  $c->response->body($output);

  return 1;
}

sub find_template {
  my ($self, $c) = @_;
  my $template = $c->stash->{template}
    ||  $c->action . $self->template_extension;

 
  unless (defined $template) {
    $c->log->debug('No template specified for rendering') if $c->debug;
    return 0;
  }

  return $template;
}

our %CACHE = ();
sub render {
  my ($self, $c, $template, $template_args) = @_;
  $c->log->debug(qq/Rendering template "$template"/) if $c->debug;

  my $local_mojo_template = $CACHE{$template} ||= do {
    my $mojo_template = $self->_mojo_template;
    my $local_mojo_template = bless +{%$mojo_template}, ref($mojo_template);

    $local_mojo_template->name($template);
    my ($namespace_part) = localtime;
    $local_mojo_template->namespace( ref($self) .'::'. $namespace_part );

    my %helpers = $self->helpers;
    foreach my $helper(keys %helpers) {
      eval qq[ package ${\$local_mojo_template->namespace}; \nsub $helper { \$self->helpers('$helper')->(\$self, \$c, \@_) }\n ];
    }


    my $template_contents = $self->path_base->file($template)->slurp;

    $local_mojo_template = $local_mojo_template->parse($template_contents);
    $local_mojo_template;
  };

  my $output = $local_mojo_template
    ->process($template_args);

  return $output;
}

sub template_vars {
  my ($self, $c) = @_;
  my %template_args = (
    c => $c,
    base => $c->req->base,
    name => $c->config->{name},
    model => $c->model,
    self => $self,
    %{$c->stash||+{}},
  );

  return %template_args;
}

sub helpers {
  my ($self, $helper) = @_;
  my %helpers = (
    test => sub {
      my ($self, $c, @args) = @_;
      return $c->action;
    },
    %{ $self->helpers || +{} },
  );

  return $helpers{$helper} if defined $helper;
  return %helpers;

}

1;

=head1 NAME

Catalyst::View::MojoTemplate - Use Mojolicious Templates for your Catalyst View

=head1 SYNOPSIS


=head1 DESCRIPTION

Use L<Mojolicous::Template> as your L<Catalyst> view.  While ths might strike some as
odd, if you are using both L<Catalyst> and L<Mojolicous> you might like the option to
share the template code and expertise.  You might also just want to use a Perlish
template system rather than a dedicated mini language (such as L<Xslate>) since you
already know Perl and don't have the time or desire to become an expert in another
system.

This works just like many other L<Catalyst> views.  It will load and render a template
based on either the current action private name or a stash variable.  It will use the
stash to populate variables in the template.  It also offers an alternative interface
that lets you set a template in the actual call to the view, and pass variables.

=head1 CONFIGURATION

This view defines the following configuration attributes.  For the most part these
are just pass thru to the underlying L<Mojo::Template>.  You would do well to review
those docs if you are not familiar.

=head2 auto_escape

True by default.  Automatically escapes template render of variables to help prevent
HTML injection attacks.

=head2 append

=head2 prepend

Appends or prepends Perl code to the compiled template.  

=head2 capture_start

=head2 capture_end

String used to mark the start and end of a capture block.  Defaults to 'start', 'end'.

=head2 encoding

Encoding of the template files.  Please note that this is only applied to decoding the
template files, it is not used to encode the rendered templates.  Defaults to UTF-8.

=head2 comment_mark

=head2 escape_mark

=head2 expression_mark

=head2 line_start

=head2 replace_mark


=head1 AUTHOR
 
    jnap - John Napiorkowski (cpan:JJNAPIORK)  L<email:jjnapiork@cpan.org>

=head1 SEE ALSO
 
L<Catalyst>, L<Catalyst::View>, L<Mojolicious>
    
=head1 COPYRIGHT & LICENSE
 
Copyright 2020, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

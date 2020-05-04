package Catalyst::View::MojoTemplate;

use Moo;
use Mojo::Template;
use Mojo::ByteStream qw(b);

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

has template_extension => (is=>'ro', required=>1, default=>sub { '.mt' });

has content_type => (is=>'ro', required=>1, default=>sub { 'text/html' });
has helpers => (is=>'ro', predicate=>'has_helpers');
has layout => (is=>'ro', predicate=>'has_layout');

has _mojo_template => (
  is => 'ro',
  init_arg => undef,
  lazy => 1,
  builder => '_build_mojo_template',
);

  sub _build_mojo_template {
    my $self = shift;
    my $prepend = 'my $c = _C;' . $self->prepend;
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
      prepend => $prepend,
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

sub ACCEPT_CONTEXT {
  my ($self, $c, @args) = @_;
  $c->stash->{'view.layout'} = $self->layout
    if $self->has_layout && !exists($c->stash->{'view.layout'});

  if(@args) {
    my %template_args = %{ pop(@args)||+{} };
    my $template = shift @args || $self->find_template($c);
    my %global_args = $self->template_vars($c);
    my $output = $self->render($c, $template, +{%global_args, %template_args});
    $self->set_response_from($c,$output);

    return $self;
  } else {
    return $self;
  }
}

sub set_response_from {
  my ($self, $c, $output) = @_;
  $c->response->content_type($self->content_type) unless $c->response->content_type;
  $c->response->body($output) unless $c->response->body;
}

sub process {
  my ($self, $c) = @_;
  my $template = $self->find_template($c); 
  my %template_args = $self->template_vars($c);
  my $output = $self->render($c, $template, \%template_args);
  $self->set_response_from($c, $output);

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

sub render {
  my ($self, $c, $template, $template_args) = @_;
  my $output = $self->render_template($c, $template, $template_args);

  if(ref $output) {
    # Its a Mojo::Exception;
    $c->response->content_type('text/plain');
    $c->response->body($output);
    return $output;
  }

  return $self->apply_layout($c, $output);
}

sub apply_layout {
  my ($self, $c, $output) = @_;
  if(my $layout = $self->find_layout($c)) {
    $c->log->debug(qq/Applying layout "$layout"/) if $c->debug;
    $c->stash->{'view.content'}->{main} = sub { b($output) };
    $output = $self->render($c, $layout, +{ $self->template_vars($c) });
  }
  return $output;
}

sub find_layout {
  my ($self, $c) = @_;
  return delete $c->stash->{'view.layout'} if exists $c->stash->{'view.layout'};
  return;
}

our %CACHE = ();
sub render_template {
  my ($self, $c, $template, $template_args) = @_;
  $c->log->debug(qq/Rendering template "$template"/) if $c->debug;

  my $local_mojo_template = $CACHE{$template} ||= do {
    my $mojo_template = $self->_mojo_template;
    my $local_mojo_template = bless +{%$mojo_template}, ref($mojo_template);

    $local_mojo_template->name($template);
    my $namespace_part = $template;
    $namespace_part =~s/\//::/g;
    $namespace_part =~s/\.mt$//;
    $local_mojo_template->namespace( ref($self) .'::Sandbox::'. $namespace_part);
    
    my $template_full_path = $self->path_base->file($template);
    $c->log->debug(qq/Found template at path "$template_full_path"/) if $c->debug;
    my $template_contents = $template_full_path->slurp;

    $local_mojo_template->parse($template_contents);
  };

  my $ns = $local_mojo_template->namespace;
  $self->inject_context($c, $ns);
  $self->inject_helpers($c, $ns) unless $self->{"__helper_${ns}"};
  $self->{"__helper_${ns}"}++;

  return my $output = $local_mojo_template->process($template_args);
}

sub inject_context {
  my($self, $c, $namespace) = @_;
  no strict 'refs';
  no warnings 'redefine';
  local *{"${namespace}::_C"} = sub {$c};
}

sub inject_helpers {
  my ($self, $c, $namespace) = @_;
  $c->log->debug(qq/Injecting Helpers into "$namespace"/) if $c->debug;
  my %helpers = $self->get_helpers;
  foreach my $helper(keys %helpers) {
    $c->log->debug(qq/Injecting helper "$helper"/) if $c->debug;
    eval qq[
      package $namespace;
      sub $helper { \$self->get_helpers('$helper')->(\$self, _C, \@_) }
    ]; die $@ if $@;
  }
}

sub template_vars {
  my ($self, $c) = @_;
  my %template_args = (
    base => $c->req->base,
    name => $c->config->{name} ||'',
    model => $c->model,
    self => $self,
    %{$c->stash||+{}},
  );

  return %template_args;
}

sub default_helpers {
  my $self = shift;
  return (
    layout => sub {
      my ($self, $c, $template, %args) = @_;
      $c->stash('view.layout' => $template);
      $c->stash(%args) if %args;
    },
    wrapper => sub {
      my ($self, $c, $template, @args) = @_;
      $c->stash->{'view.content'}->{main} = pop @args;
      my %local_args = @args;
      my %global_args = $self->template_vars($c);
      return b($self->render_template($c, $template, +{ %global_args, %local_args }));
    },
    include => sub {
      my ($self, $c, $template, %args) = @_;
      my %template_args = $self->template_vars($c);
      return b($self->render_template($c, $template, +{ %template_args, %args }));
    },
    content => sub {
      my ($self, $c, $name, $proto) = @_;
      $name ||= 'main';
      $c->stash->{'view.content'}->{$name} = $proto if $proto;

      my $value = $c->stash->{'view.content'}->{$name}
        || die "No content key named '$name'";

      return (ref($value)||'') eq 'CODE' ? $value->() : $value;
    },
    form => sub {
      my ($self, $c, $model, @proto) = @_;
      my ($inner, %attrs) = (pop(@proto), @proto);
      my $attrs =  join ' ', map { "$_='$attrs{$_}'"} keys %attrs;

      LOCAL_TO_FORM: {
        # Do we need a stack so we can refer to the parent or not...?
        my @model_stack = (
          (exists($c->stash->{'view.form.model'}) ? $c->stash->{'view.form.model'} : () ),
          $model,
        );
        local $c->stash->{'view.form.model'} = $model;

      return b("<form $attrs>@{[$inner->()]}</form>");
      }
    },
    input => sub {
      my ($self, $c, $name, %attrs) = @_;
      $attrs{value} = $c->stash->{'view.form.model'}->{$name};
      my $attrs =  join ' ', map { "$_='$attrs{$_}'"} keys %attrs;
      return b("<input $attrs/>");
    },
  );
}

sub get_helpers {
  my ($self, $helper) = @_;
  my %helpers = ($self->default_helpers, %{ $self->helpers || +{} });

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

=head2 append

=head2 prepend

=head2 capture_start

=head2 capture_end

=head2 encoding

=head2 comment_mark

=head2 escape_mark

=head2 expression_mark

=head2 line_start

=head2 replace_mark

These are just pass thru to L<Mojo::Template>.  See that for details

=head2 content_type

The HTTP content-type that is set in the response unless it is already set.

=head2 helpers

An arrayref of helper functions

=head2 layout

Set a default layout which will be used if none are defined.  Optional.

=head1 AUTHOR
 
    jnap - John Napiorkowski (cpan:JJNAPIORK)  L<email:jjnapiork@cpan.org>
    With tremendous thanks to SRI and the Mojolicous team!

=head1 SEE ALSO
 
L<Catalyst>, L<Catalyst::View>, L<Mojolicious>
    
=head1 COPYRIGHT & LICENSE
 
Copyright 2020, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

package Example::Controller::Root;

use Moose;
use MooseX::MethodAttributes;

extends 'Catalyst::Controller';

sub root :Chained(/) PathPart('') CaptureArgs(0) {} 

  sub home :Chained(root) PathPart('') Args(0) {
    my ($self, $c) = @_;
    $c->stash(test=>100);
  }

  sub profile :Chained(root) PathPart(profile) Args(0) {
    my ($self, $c) = @_;
    $c->view('HTML' => 'profile.mt', +{ aaa=> 100 });
  }

sub end : ActionClass('RenderView') {}

__PACKAGE__->config(namespace=>'');
__PACKAGE__->meta->make_immutable;

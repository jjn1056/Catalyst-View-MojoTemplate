package Example::View::HTML;

use Moose;
extends 'Catalyst::View::MojoTemplate';

#__PACKAGE__->config(layout=>'layout.mt');
__PACKAGE__->meta->make_immutable;

% layout "layout.mt", title => "Hello";
%= include "navbar.mt", myapp => "Example";
this is a testdd
<%= $test %>
ggg

% content 'test' => begin
this <b>is</b> content <%= $test %>
% end;

<hr>

%= form $person, begin
  %= input 'name';
% end
% use Devel::Dwarn; Dwarn $c->stash; warn $c;



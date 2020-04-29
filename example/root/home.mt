% layout "wrapper.mt", title => "Hello";
%= include "navbar.mt", myapp => "Example";
this is a testdd
<%= $test %>
ggg
<%= test "sdfsdfsdf" => begin %>
sdfsdfs
sdfsdf
sdfsdf
<% end %>


% content 'test' => begin
this <b>is</b> content <%= $test %>
% end;

% layout "layout.mt", title => "Hello";
%= wrapper "wrapper.mt", header => "HEAD1", begin
profile
%end
<%= $aaa %>
% content 'test' => begin
this <b>is</b> content
% end;

$(document).ready(function(){
  $("#a").click(function(){ $(".x").hide(); $("#b").addClass("on"); });
  $.ajax({url:"/rest/x"}).done(function(d){ $("#v").val(d.v); });
  $("#c").fadeIn(200);
  $("#d").datepicker({});
  $(".t").each(function(){ doStuff($(this)); });
});

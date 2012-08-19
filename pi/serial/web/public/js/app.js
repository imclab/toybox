$(function(){
  ws = new WebSocket("ws://" + window.location.hostname + ":8080");

  ws.onmessage = function(evt) {
    if ($('#chat tbody tr:first').length > 0){
      $('#chat tbody tr:first').before('<tr><td>' + evt.data + '</td></tr>');
    } else {
      $('#chat tbody').append('<tr><td>' + evt.data + '</td></tr>');
    }
  };

  ws.onclose = function() {
  };

  ws.onopen = function() {
  };

  $("#clear").click( function() {
    $('#chat tbody tr').remove();
  });

});
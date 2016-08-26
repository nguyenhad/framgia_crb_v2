$(document).on('page:change', function() {
  $('#particular-calendar').fullCalendar({
    header: {
      left: 'prev,next today',
      center: 'title',
      right: 'agendaDay, agendaWeek, month, agendaFourDay'
    },
    views: {
      agendaFourDay: {
        type: 'agenda',
        duration: {days: 4},
        buttonText: '4 days'
      }
    },
    eventColor: '#3A87AD',
    defaultView: 'month',
    editable: false,
    selectHelper: true,
    unselectAuto: false,
    nowIndicator: true,
    allDaySlot: true,
    eventLimit: true,
    allDayDefault: false,

    height: $(window).height() - $('header').height() - 9,
    events: function(start, end, timezone, callback) {
      var calendar_id = $('#particular-calendar').attr("calendar-id");
      $.ajax({
        url: '/api/particular_events',
        data: {
          calendar_id: calendar_id
        },
        type: 'GET',
        success: function(data){
          var events = [];
          events = data.map(function(event) {
            return {
              title: event.title,
              start: event.start_date,
              place_id: event.place_id,
              name_place: event.name_place,
              end: event.finish_date,
              id: event.id,
              user_id: event.user_id,
            }
          });
          callback(events);
        }
      })
    },
    eventClick: function(calEvent, jsEvent, view){
      initPopupEventClick(calEvent, jsEvent);
    }
  });

  function initPopupEventClick(event, jsEvent) {
    if ($('#popup') !== null)
      $('#popup').remove();
    $.ajax({
      url: '/api/particular_events/' + event.id,
      data: {
        start: event.start.format('MM-DD-YYYY H:mm A'),
        end: (event.end !== null) ? event.end.format('MM-DD-YYYY H:mm A') : ''
      },
      success: function(data){
        $('#particular-calendar').append(data);
        PopupCordinate(jsEvent, 'popup', 'prong-popup');
        showDialog('popup');
      }
    });
  }

  function PopupCordinate(jsEvent, dialogId, prongId) {
    var dialog = $('#' + dialogId);
    var dialogW = $(dialog).width();
    var dialogH = $(dialog).height();
    var windowW = $(window).width();
    var windowH = $(window).height();
    var xCordinate, yCordinate;
    var prongRotateX, prongXCordinate, prongYCordinate;

    if(jsEvent.clientX - dialogW/2 < 0) {
      xCordinate = jsEvent.clientX - dialogW/2 + 185;
    } else if(windowW - jsEvent.clientX < dialogW/2) {
      xCordinate = windowW - 2 * dialogW/2 - 10;
    } else {
      xCordinate = jsEvent.clientX - dialogW/2;
    }

    if(jsEvent.clientY - dialogH < 0) {
      yCordinate = jsEvent.clientY + 20;
      prongRotateX = 180;
      prongYCordinate = -9;
    } else {
      yCordinate = jsEvent.clientY - dialogH - 20;
      prongRotateX = 0;
      prongYCordinate = dialogH;
    }

    prongXCordinate = jsEvent.clientX - xCordinate - 10;

    $(dialog).css({'top': yCordinate, 'left': xCordinate});
    $('#' + prongId).css({
      'top': prongYCordinate,
      'left': prongXCordinate,
      'transform': 'rotateX(' + prongRotateX + 'deg)'
    });
  }

  function showDialog(dialogId) {
    var dialog = $('#' + dialogId);
    $(dialog).removeClass('hidden-popup');
    $(dialog).addClass('show-popup');
  }

  hiddenPopup = function(dialogId) {
    var dialog = $('#' + dialogId);
    $(dialog).addClass('hidden-popup');
    $(dialog).removeClass('show-popup');
  }

  function eventDateTimeFormat(startDate, finishDate, dayClick) {
    if (dayClick || finishDate == null) {
      return startDate.format('dddd DD-MM-YYYY');
    } else {
      return startDate.format('dddd') + ' ' + startDate.format('H:mm A') + ' To '
        + finishDate.format('H:mm A') + ' ' + finishDate.format('DD-MM-YYYY');
    }
  }
  $('#particular-calendar').on('click', '.bubble-close',function() {
    hiddenPopup('popup');
  })
});

{application, rtsp,
[{description, "RTSP handling library"},
 {vsn, "0.1"},
 {modules, [ems_rtsp,rtsp,rtsp_example_callback,rtsp_listener,rtsp_socket,rtsp_sup]},
 {registered,[rtsp]},
 {applications, [kernel,stdlib]},
 {mod, {rtsp,[]}}
]}.

function launchTimers(CLASS, DURATION, T_PERIOD, T_BLANK, T_CUE_ON, T_CUE)
%% initialize figure
addpath('disp_cue');
FigHandle = figure;
set(FigHandle, 'OuterPosition', [1680, 0, 1680, 1050]);
drawnow

fprintf(1,'Starting timers..\n');
fprintf(1,'Total duration: %d \n', DURATION);
fprintf(1,'Period length: %d \n', T_PERIOD);
%% create timer for experiment
tmr_delete_all_timers = timer('ExecutionMode', 'singleShot', ...
    'StartDelay', T_PERIOD+0.25, ...
    'TimerFcn', {@deleteAllTimers});
start(tmr_delete_all_timers);

%% create timer object for blank
tmr_blank = timer('ExecutionMode', 'FixedRate', ...
    'Period', T_PERIOD, ...
    'TimerFcn', {@draw_blank});
start(tmr_blank);

%% create timer object for cross
tmr_cross = timer('ExecutionMode', 'FixedRate', ...
    'StartDelay', T_BLANK, ...
    'Period', T_PERIOD, ...
    'TimerFcn', {@draw_cross});
start(tmr_cross);

%% create timer object for right cue
if CLASS == 1
    tmr_right = timer('ExecutionMode', 'FixedRate', ...
        'StartDelay', T_CUE_ON, ...
        'Period', 2*T_PERIOD, ...
        'TimerFcn', {@draw_rightarrow});
    start(tmr_right);
end
%% create timer object for cross after cue
tmr_cross_after_cue = timer('ExecutionMode', 'FixedRate', ...
    'StartDelay', T_CUE_ON + T_CUE, ...
    'Period', T_PERIOD, ...
    'TimerFcn', {@draw_cross});
start(tmr_cross_after_cue);

%% create timer object for left cue
if CLASS == 0
    tmr_left = timer('ExecutionMode', 'FixedRate', ...
        'StartDelay', T_CUE_ON, ...
        'Period', 2*T_PERIOD, ...
        'TimerFcn', {@draw_leftarrow});
    start(tmr_left);
end
end
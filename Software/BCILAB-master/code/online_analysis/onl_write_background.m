function onl_write_background(varargin)
% Periodically process data using a predictive model, and write results to some external device.
% onl_write_background(ResultWriter,MatlabStream,Model,OutputFormat,UpdateFrequency,StartDelay,PredictorName)
% 
% This is a convenience function which simplifies the definition of components which load and
% periodically query a predictive model, in real time, and forward the results to some external
% device. The function is internally implemented using a timer that periodically triggers the
% computation of updated estimates, and their transfer to the data sink.
%
% In:
%   ResultWriter : Function that receives one or more BCI estimates and writes them to some external
%                  device. The format is according to OutputFormat.
%
%   MatlabStream : Real-time stream name to read from (in MATLAB workspace) (default: 'laststream')
%
%   Model : Predictive model to use, or variable name (in MATLAB workspace)  (default: 'lastmodel')
%
%   OutputFormat : Output data format, see onl_predict (default: 'distribution')
%
%   UpdateFrequency : Frequency at which the device should be queried, in Hz (default: 25)
%
%   StartDelay : Delay before real-time processing begins; grace period until user resources are 
%                created (default: 1)
%
%   PredictorName : name for new predictor, in the workspace (default: 'lastpredictor')
%
%   PredictAt : Predict at markers. If nonempty, this is a cell array of online target markers 
%               relative to which predictions shall be made. If empty, predictions are always made 
%               on the most recently added sample. (default: {})
%
%   Verbose : Verbose output. If false, the console output of the online pipeline will be suppressed.
%             (default: false)
%
%   EmptyResultValue : Empty-result value. This value is returned for predictions that yielded no result.
%                      (default: NaN)
%
% Examples:
%   % after a predictive model has been learned using bci_train, and a data stream supplying raw
%   % data has been established, load the model into the online system and periodically send its 
%   % outputs to a target destination
%   onl_write_background(@send_outputs_to_destination,'mystream')
%
%   % as before, but also specify a custom output format and a higher update frequency
%   onl_write_background(@send_outputs_to_destination,'mystream','lastmodel','expectation',25)
%
%   % as before, but pass all arguments by their short names
%   onl_write_background('ResultWriter',@send_outputs_to_destination,'MatlabStream','mystream','Model','lastmodel','OutputFormat','expectation','UpdateFrequency',25)
%
% See also:
%   onl_predict
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2011-01-18

% read options
arg_define(varargin, ...
    arg_norep({'result_writer','ResultWriter'}), ...
    arg({'in_stream','MatlabStream'}, 'laststream',[],'Input Matlab stream. This is the stream that shall be analyzed and processed. Can also be a cell array of streams, if multiple, or empty if non-ambiguous.'), ...
    arg({'pred_model','Model'}, 'lastmodel', [], 'Predictive model. As obtained via bci_train or the Model Calibration dialog.','type','expression'), ...
    arg({'out_form','OutputFormat'},'distribution',{'expectation','distribution','mode'},'Format of the produced output values. Can be the expected value (posterior mean) of the target variable, or the distribution over possible target values (probabilities for each outcome, or parametric distribution), or the mode (most likely value) of the target variable.'), ...
    arg({'update_freq','UpdateFrequency'},10,[],'Update frequency. This is the rate at which the outputs should be calculated.'), ...
    arg({'start_delay','StartDelay'}, 1, [],'Start-up delay. Delay before real-time processing begins; grace period to initialize everything.'), ...
    arg({'pred_name','PredictorName'}, 'lastpredictor',[],'Name of new predictor. This is the workspace variable name under which a predictor will be created.'), ...
    arg({'predict_at','PredictAt'}, {},[],'Predict at markers. If nonempty, this is a cell array of online target markers relative to which predictions shall be made. If empty, predictions are always made on the most recently added sample.','type','expression'), ...
    arg({'verbose','Verbose'}, false,[],'Verbose output. If false, the console output of the online pipeline will be suppressed.'), ...
    arg({'empty_result_value','EmptyResultValue'},NaN,[],'Empty-result value. This value is returned for predictions that yielded no result.','type','expression'));

% create new predictor
predid = onl_newpredictor(pred_name,pred_model,in_stream,predict_at);
streamid = evalin('base',[in_stream '.streamid']);

% create & start timer (which periodically writes to the stream)
start(timer('ExecutionMode','fixedRate', 'Name',[pred_name '_timer'], 'Period',1/update_freq, ...
    'StartDelay',start_delay, 'TimerFcn',@(timer_handle,varargin) write_data(pred_name,in_stream,out_form,result_writer,predid,streamid,timer_handle,verbose,empty_result_value)));

% background data writer
function write_data(predictor,stream,fmt,result_writer,pred_id,stream_id,timer_handle,verbose,empty_result_value)
try
    % check if the stream and the predictor are still there
    s = evalin('base',stream);
    if s.streamid ~= stream_id
        error('Stream changed.'); end
    p = evalin('base',predictor);
    if p.predictorid ~= pred_id
        error('Predictor changed.'); end
    % make a prediction
    y = onl_predict(predictor,fmt,~verbose,empty_result_value);
    % and write it out
    try
        result_writer(y);
    catch e
        disp('Error in result-writing function:');
        hlp_handleerror(e);
    end
catch e
    if ~strcmp(e.identifier,'MATLAB:UndefinedFunction')
        hlp_handleerror(e); end    
    % stream or predictor have changed (e.g., replaced/deleted) --> stop timer
    stop(timer_handle);
    delete(timer_handle);
end

function pipeline = onl_newpipeline(filterapp, streams, needed_channels)
% Create a new filter pipeline from a filter expression and a set of stream names to bind to.
% Pipeline = onl_newpipeline(FilterExpression, StreamNames, NeededChannels)
%
% This is an expert function that is not needed for normal BCILAB operation. See onl_filtered
% for more details.
%
% In:
%   FilterApplication : The result of applying some filter chain to a calibration data set.
%                       This contains as an annotation the necessary information to resume the 
%                       processing online on raw data (e.g. filter state, etc.).
%
%   Streams : optional names of streams (previously created with onl_newstream) to consider as
%             possible data sources; any stream that contains channels that are needed by the
%             predictor will be linked to it (assuming that the choice of stream to use is not
%             ambiguous). 
%
%             The identification of needed channels is primarily done on the basis of the channel
%             labels -- if a stream has channels with labels that are required by a filter pipeline,
%             it will be used as a source for this pipeline. The framework attempts to gracefully
%             handle cases where a stream only provides a subset of the channels that were in the 
%             training set and the model only effectively operates on this subset via flt_selchans.
%
%   NeededChannels : optionally a cell array of channel names that shall be present in the output of 
%                    the pipeline (default: all)
%                     
%                    By specifying this, you can bind the pipeline to streams that are lacking some
%                    of the channels that the pipeline expects (e.g. in a flt_selchans), but you as 
%                    the final consumer don't need.
%
% Out:
%   Pipeline : a new filter pipeline struct.
%
% See also:
%   onl_newstream, onl_append, onl_filtered
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2012-05-13

% handle the pipeline description (filter application)
if ~exist('filterapp','var')
    error('Please specify a filter expression to wrap into a pipeline.'); end

% take the online expression if not yet done so
if isfield(filterapp,'tracking') && isfield(filterapp.tracking,'online_expression')
    filterapp = filterapp.tracking.online_expression; end

% evaluate the pipeline description if not yet done so
if isempty(utl_find_filter(filterapp,'rawdata'))
    filterapp = exp_eval_optimized(filterapp); 
    filterapp = filterapp.tracking.online_expression; 
end

% final sanity check
if ~all(isfield(filterapp,{'head','parts'}))
    error('The given data does not describe a filter application.'); end

% get the streams
if ~exist('streams','var') || isempty(streams)
    % find all admissible streams in the workspace....
    vars = evalin('base','whos');
    vars = vars(strcmp({vars.class},'struct'));
    streams = {vars(cellfun(@(x)all(isfield(evalin('base',x),{'buffer','smax'})),{vars.name})).name};
end

% streams sanity checks
if ~iscell(streams)
    streams = {streams}; end
for s=1:length(streams)
    if ~ischar(streams{s})
        error('BCILAB:onl_newpipeline:invalid_streams','The Streams argument must be passed as the names under which the streams were loaded, instead of as structs.'); end
    if ~isvarname(streams{s})
        error('BCILAB:onl_newpipeline:invalid_streams','One of the supplied stream names is not a valid matlab variable name (and thus cannot refer to a stream): %s.',streams{s}); end
end

if ~exist('needed_channels','var')
    needed_channels = []; end

try    
    % resolve the rawdata nodes into the correct stream
    pipeline = utl_resolve_streams(filterapp,streams,needed_channels);
    % initialize misc properties of the pipeline
    pipeline = init_pipeline(pipeline);
catch e
    hlp_handleerror(e);
    error('BCILAB:onl_newpipeline:unexpected','Could not match the channels required by the pipeline with what the stream provides.');
end


% initialize fields of a filter pipeline for efficient online use
function p = init_pipeline(p)
% check if this is a raw-data (leaf) node
if ~strcmp(char(p.head),'rawdata')
    % the .subnodes field stores which of the input arguments are pipelines
    % (that we need to update recursively)
    p.subnodes = find(cellfun(@(x)all(isfield(x,{'head','parts'})),p.parts));
    % the .stateful field denotes whether the filter function returns state
    if ~isfield(p,'stateful')
        p.stateful = is_stateful(p.head); end
    % the .state field contains the previous state of the filter function
    if p.stateful && ~isfield(p,'state')
        p.state = []; end
    % recursively initialize the sub-pipelines
    for k = p.subnodes
        p.parts{k} = init_pipeline(p.parts{k}); end
else
    % for raw streams all we need initially is the smax (number of samples seen so far)
    p.smax = 0;
    p.subnodes = [];
end

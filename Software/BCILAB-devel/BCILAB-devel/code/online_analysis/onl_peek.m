function chunk = onl_peek(streamname,samples_to_get,unit,channels_to_get)
% Peek into an online stream (generates an EEG-set like view into it).
% Chunk = onl_peek(StreamName,DesiredLength,LengthUnit,DesiredChannels)
%
% This function returns an EEGLAB dataset struct that hold the last k seconds of an online stream.
% An online stream is a data structure in the workspace that can be created with onl_newstream;
% data can be appended to it by onl_append or onl_read_background.
%
% In:
%   StreamName : Name of the online stream data structure in the MATLAB workspace to read from.
%                Must have previously been created with onl_newstream.
%
%   DesiredLength : length of the view that should be generated; should not be longer than the
%                   buffer capacity (default: 10)
%
%   LengthUnit : Can be one of the following options:
%                 * 'seconds': return the last PeekLength seconds (default)
%                 * 'samples': return the last PeekLength samples
%                 * 'index': return all samples newer than PeekLength (as a sample index)
%
%   DesiredChannels : range of channels to return ([] = all channels); (default: [])
%
% Out:
%   Chunk : An EEGLAB data set that contains the most recent data of a given stream
%
% Example:
%   % get the last 5 seconds of the stream
%   EEG = onl_peek('mystream',5)
%
%   % get the last 128 samples of the stream
%   EEG = onl_peek('mystream',128,'samples')
%
%   % get all samples past the 5000'th sample in the stream
%   EEG = onl_peek('mystream',5000,'index')
%
%   % get the default amount of data, for channels 1:10
%   EEG = onl_peek('mystream',[],[],1:10)
%
% See also:
%   onl_newstream, onl_append, onl_filtered
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2010-04-03

% try to get the stream from the base workspace
try
    chunk = evalin('base',streamname);
catch e
    % diagnose the error
    if nargin < 1
        error('You need to pass at least the name of a previously created stream.'); end
    if ~ischar(streamname) || isempty(streamname) || ~isvarname(streamname)
        error('The given StreamName argument must be the name of a variable name in the MATLAB workspace, but was: %s',hlp_tostring(streamname,10000)); end
    if strcmp(e.identifier,'MATLAB:badsubscript')
        error('BCILAB:onl_peek:improper_resolve','The raw data required by the predictor does not list the name of the needed source stream; this is likely a problem in onl_newstream/onl_newpredictor.');
    else
        error('BCILAB:onl_peek:stream_not_found','The stream named %s was not found in the base workspace.',hlp_tostring(streamname));
    end
end

try
    % set further default arguments
    if nargin < 4 || isempty(channels_to_get)
        channels_to_get = 1:size(chunk.buffer,1);
        if nargin < 3 || isempty(unit)
            unit = 'seconds'; end
        if nargin < 2 || isempty(samples_to_get)
            samples_to_get = 10; end
    end

    % determine the amount of data needed
    switch unit
        case 'index'
            samples_to_get = min(chunk.buffer_len,chunk.smax-samples_to_get);
        case 'samples'
            samples_to_get = min(chunk.buffer_len,samples_to_get);
        case 'seconds'        
            samples_to_get = min(chunk.buffer_len,round(chunk.srate*samples_to_get));
        otherwise
            error('Unrecognized LengthUnit specified: %s',hlp_tostring(unit));
    end
    
    % extract the desired interval from the .buffer field and move it to .data
    range = 1+mod(chunk.smax-samples_to_get:chunk.smax-1,chunk.buffer_len);
    chunk.data = chunk.buffer(channels_to_get,range);

    % extract the markers, if there are any
    if chunk.mmax
        [ranks,sample_indices,record_indices] = find(chunk.marker_pos(:,range));
        if any(ranks)
            chunk.event = chunk.marker_buffer(1+mod(record_indices-1,chunk.marker_buffer_len));
            [chunk.event.latency] = arraydeal(sample_indices(:) + [chunk.event.latency]');
        end
    end
    
    % update meta-data
    [chunk.nbchan,chunk.pnts,chunk.trials] = size(chunk.data);
    chunk.chanlocs = chunk.chanlocs(channels_to_get);
    if chunk.xmin == 0
        chunk.xmax = (chunk.smax-1)/chunk.srate;
        chunk.xmin = chunk.xmax - (chunk.pnts-1)/chunk.srate;
    else
        chunk.xmax = chunk.xmin + (chunk.pnts-1)/chunk.srate;
    end

catch e
    if ~ischar(unit) || isempty(unit)
        error('The given Unit argument must be a string, but was: %s',hlp_tostring(unit,10000)); end
    if ~isnumeric(samples_to_get) || ~isscalar(samples_to_get)
        error('The given DesiredLength argument must be a numeric scalar, but was: %s',hlp_tostring(samples_to_get,10000)); end
    if ~isnumeric(channels_to_get) || min(size(channels_to_get) ~= 1)
        error('The given DesiredChannels argument must be a numeric vector, but was: %s',hlp_tostring(channels_to_get,10000)); end
    error('Failed to read from stream %s with error: %s\nPossibly the stream variable has been overwritten or you have the wrong name.',streamname,e.message);
end

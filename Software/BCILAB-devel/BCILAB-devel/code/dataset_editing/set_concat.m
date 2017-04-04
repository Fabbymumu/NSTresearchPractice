function result = set_concat(varargin)
% Concatenate continuous signals across time.
% Result = set_joinepos(Set1, Set2, ...)
%
% In:
%   SetK   : The k'th data set to concatenate.
%
% Out:
%   Result : A new data set that is the concatenation of all input sets. The following changes are made:
%            * .data and all other time-series fields are concatenated across time (2nd dimension)
%            * .event is joined and .latency fields are updated appropriately
%            * .xmax/.pnts are updated
%
% Notes:
%   This function returns a new data set with meta-data set to that of the first input set, and the
%   time series fields joined across all sets. No checks for meta-data consistency are done. There
%   is a heavy-duty function for merging inconsistent sets called set_merge, which can merge cats
%   and dogs. This function does not attempt to keep miscellaneous EEGLAB meta-data consistent,
%   including: setname,filename,filepath,subject,group,condition,session,comments,urevent,reject,stats,history,etc
%
% Examples:
%   % concatenate data sets eegA, eegB and eegC across time
%   eeg = set_concat(eegA,eegB,eegC)
%
% See also:
%   set_joinepos, set_merge
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2010-03-31
dp;

% set_concat_version<1.0> -- for the cache

if ~exp_beginfun('editing') return; end

declare_properties('name','Concatenate','independent_channels',true,'independent_trials',false);

% input validation
for k=1:length(varargin)
    utl_check_fields(varargin{k},{'data','event','pnts','xmin','xmax','srate'},'input','signal');
    if ~isempty(varargin{k}.event)
        if ~isfield(varargin{k}.event,'latency')
            error('A dataset passed to set_concat is lacking the .event.latency field.'); end
        latency_numels = cellfun('prodofsize',{varargin{k}.event.latency});
        if any(latency_numels == 0)
            error('One or more of the events in the given data set have an empty .latency field, which is not permitted.'); end
        if any(latency_numels ~= 1)
            error('One or more of the events in the given data set have a .latency value that is not a scalar, which is not permitted.'); end
    end
    if isfield(varargin{k},'epoch') && ~isempty(varargin{k}.epoch)
        error('Only continuous data can be concatenated with set_concat -- use set_joinepos for epoched data.'); end        
end

if ~isempty(varargin)
    result = varargin{1};
    if length(varargin) > 1
        % concatenate time series fields
        for field = utl_timeseries_fields(result)
            data = cellfun(@(x)x.(field{1}),varargin,'UniformOutput',false);
            try
                result.(field{1}) = cat(2,data{:}); 
            catch e
                % concatenation failed: produce a reasonable error message
                if ~isempty(data)
                    sizes = cellfun('size',data,1);
                    sizes = sizes(sizes ~= 0);
                    if length(sizes) > 1 && ~all(sizes==sizes(1))
                        error('The time-series field .%s must have the same number of channels in each data set.',field{1}); end
                    if any(cellfun('size',data,3) > 1)
                        error('One or more of the datasets passed to set_concat were epoched -- use set_joinepos to concatenate epoched data.'); end
                end
                size_info = hlp_tostring(cellfun(@size,data,'UniformOutput',false));
                error('Concatenation of time-series fields failed with error: %s (the data sizes were %s -- make sure that they are mutually compatible).',e.message,size_info);
            end
            if isempty(result.(field{1}))
                result.(field{1}) = []; end
        end
        % count events, epochs and samples in each set
        event_count = cellfun(@(x)length(x.event),varargin);
        sample_count = cellfun(@(x)x.pnts,varargin);
        % concatenate .event and .epoch fields
        event = cellfun(@(x)x.event,varargin,'UniformOutput',false); result.event = [event{:}];
        % shift event latencies based on cumulative sample counts
        if ~isempty(result.event)
            [result.event.latency] = arraydeal([result.event.latency]+replicate(cumsum(sample_count)-sample_count,event_count)); end
        % update misc fields
        [result.nbchan,result.pnts,result.trials,extra_dims] = size(result.data); %#ok<ASGLU,NASGU>
        result.xmax = result.xmin + (result.pnts-1)/result.srate;
    end
else
    result = struct('setname','','filename','','filepath','','subject','','group','','condition','','session',[],'comments','','nbchan',0,...
        'trials',0,'pnts',0,'srate',1,'xmin',0,'xmax',0,'times',[],'data',[],'icaact',[],'icawinv',[],'icasphere',[],'icaweights',[], ...
        'icachansind',[],'chanlocs',[],'urchanlocs',[],'chaninfo',[],'ref',[],'event',[],'urevent',[],'eventdescription',{{}}, ...
        'epoch',[],'epochdescription',{{}},'reject',[],'stats',[],'specdata',[],'specicaact',[],'splinefile','','icasplinefile','', ...
        'dipfit',[],'history','','saved','no','etc',[]);
end

exp_endfun;

function result = replicate(values,counts)
% Replicate each element Values(k) by Count(k) times.
result = zeros(1,sum(counts));
k = 0;
for p=find(counts)
    result(k+(1:counts(p))) = values(p);
    k = k+counts(p);
end

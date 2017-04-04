function signal = flt_clean_channels(varargin)
% Remove channels with abnormal data from a continuous data set.
% Signal = flt_clean_channels(Signal,MinCorrelation,IgnoredQuantile,WindowLength,MaxBrokenTime,Rereferenced)
%
% This is an automated artifact rejection function which ensures that the data contains no channels
% that record only noise for extended periods of time. If channels with control signals are
% contained in the data these are usually also removed. There are two threshold criteria: one is a
% minimum required correlation between a channel and a surrogate of it calculated from its neighbors
% using spline interpolation (calculated in a manner that is robust to bad channels in the
% neighborhood) and the other is a maximum tolerated noise level in standard deviations relative to
% the remaining channels (also robust).
%
% In:
%   Signal          : Continuous data set, assumed to be appropriately high-passed (e.g. >0.5Hz or
%                     with a 0.5Hz - 2.0Hz transition band).
%
%   CorrelationThreshold : Correlation threshold. If a channel is correlated at less than this value
%                          to its reconstruction from other channels, it is considered abnormal in
%                          the given time window. Note that this method can only be used when
%                          channel locations are available. (default: 0.8)
%
%   LineNoiseThreshold : If a channel has more line noise relative to its signal than this value, in
%                        standard deviations from the channel population mean, it is considered abnormal.
%                        (default: 4)
%
%   InitializeOn : Initialize on time range. If a time range is given as [start,end], either in 
%                  seconds or as fractions of the whole data (if both <= 1), then where applicable 
%                  the filter will be initialized only on that subset of the whole data. As a 
%                  result, the filter will not have to be retrained in each cross-validation 
%                  fold. (default: [])
%
%   The following are "detail" parameters that usually do not have to be tuned. If you can't get
%   the function to do what you want, you might consider adapting these to your data.
%   
%   NumSamples : Number of RANSAC samples. This is the number of samples to generate in the random
%                sampling consensus process. (default: 50)
%
%   SubsetSize : Subset size. This is the size of the channel subsets to use, as a fraction of the
%                total number of channels. (default: 0.25)
%
%   WindowLength    : Length of the windows (in seconds) for which correlation is computed; ideally
%                     short enough to reasonably capture periods of global artifacts or intermittent 
%                     sensor dropouts, but not shorter (for statistical reasons). (default: 5)
% 
%   MaxBrokenTime : Maximum time (either in seconds or as fraction of the recording) during which a 
%                   retained channel may be broken. Reasonable range: 0.1 (very aggressive) to 0.6
%                   (very lax). (default: 0.4)
%
%	ProtectChannels : list of channel names (cell array) that should be protected from removal. 
%                     (default: {})
%
%
% The following arguments are deprecated but retained for backwards compatibility:
%
%   Rereferenced    : Whether the measures should be computed on re-referenced data. This can improve 
%                     performance in environments with extreme EM noise, but will decrease robustness 
%                     against individual channels with extreme excursions. (default: false)
%
%   LineNoiseAware : Whether the operation should be performed in a line-noise aware manner. If enabled,
%                    the correlation measure will not be affected by the presence or absence of line 
%                    noise. (default: true).
%
%   MinCorrelation  : Minimum correlation between a channel and any other channel (in a short period 
%                     of time) below which the channel is considered abnormal for that time period.
%                     Reasonable range: 0.4 (very lax) to 0.6 (quite aggressive). (default: 0.5). 
%                     
%   IgnoredQuantile : Fraction of channels that need to have at least the given MinCorrelation value
%                     w.r.t. the channel under consideration. This allows to deal with channels or
%                     small groups of channels that measure the same noise source, e.g. if they are
%                     shorted. If many channels can be disconnected during an experiment and you
%                     have strong noise in the room, you might increase this fraction, but consider
%                     that this a) requires you to decrease the MinCorrelation appropriately and b)
%                     can make the correlation measure more brittle. Reasonable range: 0.05 (rather
%                     lax) to 0.2 (very tolerant re disconnected/shorted channels).The default is
%                     0.1.
%
% Out:
%   Signal : data set with bad channels removed
%
% Examples:
%   % use with defaults
%   eeg = flt_clean_channels(eeg);
%
%   % override the MinimumCorrelation and the IgnoredQuantile defaults
%   eeg = flt_clean_channels(eeg,0.7,0.15);
%
%   % override the MinimumCorrelation and the MaxIgnoredTime, using name-value pairs
%   eeg = flt_clean_channels('Signal',eeg,'MinimumCorrelation',0.7, 'MaxBrokenTime',0.15);
%
%   % override the MinimumCorrelation and the MaxIgnoredTime, using name-value pairs 
%   % in their short forms
%   eeg = flt_clean_channels('signal',eeg,'min_corr',0.7, 'max_broken_time',0.15);
%
% See also:
%   flt_clean_settings
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2014-05-12

% flt_clean_channels_version<0.9.8c> -- for the cache

if ~exp_beginfun('filter') return; end;

declare_properties('name','ChannelCleaning', 'independent_channels',false, 'independent_trials','initialize_on');

arg_define(varargin, ...
    arg_norep({'signal','Signal'}), ...
    arg({'corr_threshold','CorrelationThreshold'}, 0.8, [0 0.3 0.95 1], 'Correlation threshold. If a channel is correlated at less than this value to its reconstruction from other channels, it is considered abnormal in the given time window. Note that this method can only be used when channel locations are available.'), ...
    arg({'noise_threshold','LineNoiseThreshold'},4,[],'Line-noise threshold. If a channel has more line noise relative to its signal than this value, in standard deviations from the channel population mean, it is considered abnormal.'), ...
    arg({'window_len','WindowLength'}, 5, [0 0.25 5 Inf], 'Window length to compute correlations. Length of the windows (in seconds) for which correlation is computed; ideally short enough to reasonably capture periods of global artifacts (which are ignored), but not shorter (for statistica reasons).'), ...
    arg({'max_broken_time','MaxBrokenTime','ignored_time','MaxIgnoredTime'}, 0.4, [0 Inf], 'Maximum duration/fraction of broken data to tolerate. Maximum time (either in seconds or as fraction of the recording) during which a retained channel may be broken. Reasonable range: 0.1 (very aggressive) to 0.6 (very lax).'), ...
    arg({'subset_size','SubsetSize'}, 0.15, [0 0.1 0.3 1], 'Subset size. This is the size of the channel subsets to use, as number of channels or a fraction of the total number of channels. Lower numbers (e.g., 0.15) will yield better robustness in the presence of very noisy channels, but that requires a higher number of samples to compensate for the reduction in data.'), ...
    arg({'num_samples','NumSamples'}, 200, uint32([1 50 500 10000]), 'Number of RANSAC samples. This is the number of samples to generate in the random sampling consensus process. The more samples you use the more stable the estimates are going to be.'), ...
    arg({'protect_channels','ProtectChannels'},[],[],'Channels to protect from removal. This protects the channels with the given names from being removed.','type','cellstr','shape','row'), ...
    arg({'initialize_on','InitializeOn'},[],[0 0 600 Inf],'Initialize on time range. If a time range is given as [start,end], either in seconds or as fractions of the whole data (if both <= 1), then where applicable the filter will be initialized only on that subset of the whole data. As a result, it will not have to be retrained in each cross-validation fold.','shape','row'),...
    arg({'keep_unlocalized_channels','KeepUnlocalizedChannels'},false,[],'Keep unlocalized channels. Whether to keep channels which have no localiztion information and can therefore not be checked based on location information.'), ...
    arg({'use_gpu','UseGPU'}, false, [], 'Whether to run on the GPU. Makes sense for offline processing if you have a GTX Titan or better.'), ...
    arg({'ignore_chanlocs','IgnoreChanlocs'}, false, [], 'Ignore channel locations. If enabled, a fallback algorithm will be used that relies on the MinimumCorrelation and IgnoredQuantile parameters; this method is also used if no channel locations are present.'), ...
    arg({'min_corr','MinimumCorrelation'}, 0.5, [0 1], 'Minimum correlation between channels. If the measure falls below this threshold in some time window, the window is considered abnormal.'), ...
    arg({'ignored_quantile','IgnoredQuantile'}, 0.1, [0 1], 'Quantile of highest correlations ignored. Upper quantile of the correlation values that may be arbitrarily high without affecting the outcome - avoids problems with shorted channels.'), ...
    arg_deprecated({'linenoise_aware','LineNoiseAware'},true,[],'Line-noise aware processing. Whether the operation should be performed in a line-noise aware manner. If enabled, the correlation measure will not be affected by the presence or absence of line noise.','guru',true), ...
    arg_deprecated({'rereferenced','Rereferenced'},false,[],'Run calculations on re-referenced data. This can improve performance in environments with extreme EM noise, but will decrease robustness against individual channels with extreme excursions.'), ...
    arg_norep('removed_channel_mask',unassigned)); 

% flag channels
if ~exist('removed_channel_mask','var')
    if ~isempty(initialize_on)
        ref_section = exp_eval(set_selinterval(signal,initialize_on,quickif(all(initialize_on<=1),'fraction','seconds')));
    else
        ref_section = signal;
    end 
    subset_size = round(subset_size*size(ref_section.data,1)); 

    if max_broken_time > 0 && max_broken_time < 1  %#ok<*NODEF>
        max_broken_time = size(ref_section.data,2)*max_broken_time;
    else
        max_broken_time = ref_section.srate*max_broken_time;
    end
    
    [C,S] = size(ref_section.data);
    window_len = window_len*signal.srate;
    wnd = 0:window_len-1;
    offsets = round(1:window_len:S-window_len);
    W = length(offsets);

    if linenoise_aware && ref_section.srate > 100
        % remove signal content above 50Hz
        B = design_fir(100,[2*[0 45 50]/ref_section.srate 1],[1 1 0 0]);
        for c=ref_section.nbchan:-1:1
            X(:,c) = filtfilt_fast(B,1,ref_section.data(c,:)'); end
        % determine z-scored level of EM noise-to-signal ratio for each channel
        noisiness = mad(ref_section.data'-X,1)./mad(X,1);
        znoise = (noisiness - median(noisiness)) ./ (mad(noisiness,1)*1.4826);        
        % trim channels based on that
        noise_mask = znoise > noise_threshold;
    else
        X = ref_section.data';
        noise_mask = false(C,1);
    end

    % optionally subtract common reference from data
    if rereferenced
        X = bsxfun(@minus,X,mean(X,2)); end
    
    if (isfield(ref_section.chanlocs,'X') && isfield(ref_section.chanlocs,'Y') && isfield(ref_section.chanlocs,'Z') && all([length([ref_section.chanlocs.X]),length([ref_section.chanlocs.Y]),length([ref_section.chanlocs.Z])] > length(ref_section.chanlocs)*0.5)) && ~ignore_chanlocs
        fprintf('Scanning for bad channels...');
        
        % get the matrix of all channel locations [3xN]
        [x,y,z] = deal({ref_section.chanlocs.X},{ref_section.chanlocs.Y},{ref_section.chanlocs.Z});
        usable_channels = find(~cellfun('isempty',x) & ~cellfun('isempty',y) & ~cellfun('isempty',z));
        locs = [cell2mat(x(usable_channels));cell2mat(y(usable_channels));cell2mat(z(usable_channels))];
        X = X(:,usable_channels);
        
        P = hlp_diskcache('filterdesign',@calc_projector,locs,num_samples,subset_size);
        corrs = zeros(length(usable_channels),W);

        % optionally move data to the GPU
        if use_gpu
            try
                X = gpuArray(X);
                corrs = gpuArray(X);
            catch
            end
        end

        % calculate each channel's correlation to its RANSAC reconstruction for each window
        tic;
        for o=1:W
            XX = X(offsets(o)+wnd,:);
            YY = reshape(XX*P,[],num_samples)';
            if use_gpu
                YY = median(YY);
            else
                YY = fast_median(YY);
            end
            YY = reshape(YY,length(wnd),length(usable_channels));
            corrs(:,o) = sum(XX.*YY)./(sqrt(sum(XX.^2)).*sqrt(sum(YY.^2)));
        end
        
        % get the data back from the GPU
        if use_gpu
            corrs = gather(corrs); end
        
        flagged = corrs < corr_threshold;
        
        % mark all channels for removal which have more flagged samples than the maximum number of
        % ignored samples
        removed_channel_mask = quickif(keep_unlocalized_channels,false(C,1),true(C,1));
        removed_channel_mask(usable_channels) = sum(flagged,2)*window_len > max_broken_time;
    else
        fprintf('Not using channel locations for bad-channel removal...');    
        % for each window, flag channels with too low correlation to any other channel (outside the
        % ignored quantile)
        flagged = zeros(C,W);
        retained = 1:(C-ceil(C*ignored_quantile));
        for o=1:W
            sortcc = sort(abs(corrcoef(X(offsets(o)+wnd,:))));
            flagged(:,o) = all(sortcc(retained,:) < min_corr);
        end
        % mark all channels for removal which have more flagged samples than the maximum number of
        % ignored samples
        removed_channel_mask = sum(flagged,2)*window_len > max_broken_time;        
    end
    
    % also incorporate the line noise criterion
    removed_channel_mask = removed_channel_mask(:) | noise_mask(:);
    
    fprintf(' removing %i channels...\n',nnz(removed_channel_mask));
    % remove the channels in the protect list
    if ~isempty(protect_channels)
        removed_channel_mask(set_chanid(ref_section,protect_channels)) = true; end    
end

% annotate the data with what was removed (for visualization)
if ~isfield(signal.etc,'clean_channel_mask')
    signal.etc.clean_channel_mask = true(1,signal.nbchan); end
signal.etc.clean_channel_mask(signal.etc.clean_channel_mask) = ~removed_channel_mask;

% execute
if any(removed_channel_mask)
    signal.data = signal.data(~removed_channel_mask,:,:,:,:,:,:,:);
    signal.chanlocs = signal.chanlocs(~removed_channel_mask);
    signal.nbchan = size(signal.data,1);
end

exp_endfun('append_online',{'removed_channel_mask',removed_channel_mask});


% calculate a bag of reconstruction matrices from random channel subsets
function P = calc_projector(locs,num_samples,subset_size)
% calc_projector_version<0.9.0> -- for the cache
fprintf('flt_clean_channels: analyzing correlation structure of cap, this may take a while on first run...\n');
stream = RandStream('mt19937ar','Seed',435656);
rand_samples = {};
for k=num_samples:-1:1
    tmp = zeros(size(locs,2));
    subset = randsample(1:size(locs,2),subset_size,stream);
    tmp(subset,:) = real(sphericalSplineInterpolate(locs(:,subset),locs))';
    rand_samples{k} = tmp;
end
P = horzcat(rand_samples{:});


function Y = randsample(X,num,stream)
Y = [];
while length(Y)<num
    pick = round(1 + (length(X)-1).*rand(stream));
    Y(end+1) = X(pick);
    X(pick) = [];
end

function Y = mad(X,usemedians)
if usemedians
    Y = median(abs(bsxfun(@minus,X,median(X))));
else
    Y = mean(abs(bsxfun(@minus,X,mean(X))));
end

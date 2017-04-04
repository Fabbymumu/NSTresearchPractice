function signal = flt_clean_settings(varargin)
% Clean EEG data according to a particular cleaning setting.
% Signal = flt_clean_settings(Signal,Setting)
%
% This function calls the other cleaning functions according to a particular cleaning setting. Each
% setting corresponds to default values for the artifact removal functions in BCILAB, and the
% defaults can be further customized by passing in additional sub-options (see below). In addition,
% the function offers some general parameters that apply to all settings (e.g., whether used filters
% shall be FIR or IIR.
%
% In:
%   Signal   : continuous data set to process
%
%   Setting  : Degree of data cleaning to apply. The default is relatively versatile and should work
%              reasonably well across a range of circumstances, from seated lab experiments to
%              outdoor walking. 
%
%              Note that each of these levels has sub-parameters which can be selectively overridden
%              by passing the CleaningLevel as a cell arrays, as in: 
%               {'1.1-beta', 'BadChannelRemoval', {'MinimumCorrelation',0.25, 'WindowLength',0.5}}
%
%              The arguments that can be passed to customize a cleaning level are the following:
%               'FlatlineRemoval'   : parameters that govern how flat-line channels are removed
%                                     (see flt_clean_flatlines)
%               'SpikeRemoval'      : parameters that govern how spikes are removed (see
%                                     flt_clean_spikes)
%               'DriftRemoval'      : parameters that control the removal of drifts
%                                     (transition band of a highpass filter)
%               'HighFreqNoiseRemoval' : parameters that allow for removal of high-freq noise
%                                        (transition band of a low-pass filter)
%               'ArtifactRegression': parameters that allow for removing of reference artifacts by 
%                                     regression (see flt_eog)
%               'BadChannelRemoval' : parameters that control the removal of bad channels
%                                     (all parameters of flt_clean_channels are applicable here)
%               'BadWindowRemoval'  : parameters that control the removal of bad time windows
%                                     (all parameters of flt_clean_windows are applicable here)
%               'BadSubspaceRemoval': parameters that control the removal of local (in time and
%                                     space) artifact subspaces of the data; note that, since
%                                     artifacts are being replaced by zeros here, a subtle coupling
%                                     between the resulting data statistics and the original
%                                     artifacts is being introduced (all parameters of
%                                     flt_clean_peaks are applicable here)
%               'GlitchRemoval'     : allows for repairing temporary glitches/dropouts in channels;
%                                     this method can alter details of the signal, only use if 
%                                     really necessary  (see flt_repair_channels)
%               'BurstRemoval'      : repair short-term high-amplitude bursts in the signal (see
%                                     flt_repair_bursts)
%               'SpectrumShaping'   : parameters of a final FIR filter to reshape the spectrum
%                                     of the data arbitrarily (usually disabled) (all parameters of
%                                     flt_fir are applicable here)
%
%   RetainPhases : Retain signal phases. If this is checked, the drift-correction will be done using
%                  a linear-phase FIR filter (which incurs significant signal delay) instead of IIR.
%                  (default: false)
%
%   PreferFIR : Prefer FIR over IIR filters. The IIR filters make extensive use of the signal 
%               processing toolbox. (default: true)
%
%   CausalFiltering : Perform causal filtering. Required for online processing, strongly 
%                     recommended for any type of prediction-related offline processing but 
%                     disabling this can be potentially useful for plotting and interpretation.
%                     (default: true)
%
%   InitializeOn : Initialize on time range. If a time range is given as [start,end], either in 
%                  seconds or as fractions of the whole data (if both <= 1), then where applicable 
%                  the filters will be initialized only on that subset of the whole data. As a 
%                  result, artifact filters will not have to be retrained in each cross-validation 
%                  fold. This does not apply to the BadWindowRemoval filter. (default: [])
%
%
% Out:
%   Signal : cleaned data set
%
% Notes:
%	The available settings fall into two areas: versioned settings, such as '1.1-beta'. These
%	correspond to the bcilab release where they were first introduced, and the
%   intent is to keep the parameters and behaviors of these settings unchanged over multiple
%   releases (until they are eventually deprecated). The second area are feature-based settings,
%   where the setting lists the artifact types that are being handled. The behavior of these
%   settings will be upgraded slightly from one bcilab version to the next as new improvements are
%   found.
%
% Examples:
%   % clean the data using the 'walking' setting
%   CleanEEG = flt_clean_settings(RawEEG, 'walking')
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2012-01-27

declare_properties('name','DataCleaning', 'cannot_follow','set_makepos', 'follows','flt_selchans', 'precedes','flt_laplace', 'independent_channels',false, 'independent_trials',false);

% a function that creates a list of cleaning parameters, for some defaults
make_clean_params = @(flatlines,drifts,hf_cutoff,regression,windows,channels,dropouts,peaks,spikes,shaping) { ...
    arg_subtoggle({'flatlines','FlatlineRemoval','FlatlineCleaning'},flatlines,@flt_clean_flatlines,'Removal of flat-line channels.'), ...
    arg_subtoggle({'spikes','SpikeRemoval','pcaspikes','SpikeSubspaceRemoval'},spikes,@flt_clean_spikes,'Removal of spikes.'), ...
    arg({'drifts','DriftCutoff','DriftRemoval'},drifts,[0 0.01 2 Inf],'Drift-correction high-pass filter. This is the frequency specification of the filter: [transition-start, transition-end], in Hz'), ...
    arg_subtoggle({'hf_noise','HighFreqNoiseRemoval'},quickif(~isempty(hf_cutoff),{'Frequencies',hf_cutoff,'Mode','lowpass'},[]),@flt_fir,'Removal of high-frequency noise.','suppress',{'Type'}), ...
    arg_subtoggle({'regression','EOGRemoval','ArtifactRegression'},regression,@flt_eog,'Removal of artifacts based on reference channels.'), ...
    arg_subtoggle({'channels','ChannelRemoval','BadChannelRemoval','ChannelCleaning'},channels,@flt_clean_channels,'Removal of channels with uncorrelated signals.'), ...
    arg_subtoggle({'dropouts','DropoutRemoval','ChannelDropoutRepair','ChannelRepair','GlitchRemoval'},dropouts,@flt_repair_channels,'Repair of channels that temporarily glitch out.'), ...
    arg_subtoggle({'pcasubspace','BurstRemoval','BadSubspaceRemoval','BurstRepair','bursts'},peaks,@flt_repair_bursts,'Repair of high-power subspaces per window.'), ...
    arg_subtoggle({'windows','WindowRemoval','BadWindowRemoval','WindowCleaning'},windows,@flt_clean_windows,'Removal of time windows with excessive signal power.'), ...
    arg_subtoggle({'shaping','SpectrumShaping'},shaping,@flt_fir,'Reshaping of the signal spectrum. Done after all other steps, using a FIR filter.','experimental',true)};

% define arguments
arg_define(varargin, ...
    arg_norep({'signal','Signal'}), ...
    arg_subswitch({'cleansetting','DataSetting','Setting'},'1.1-beta', ...
        {'off',make_clean_params([],[],[],[],[],[],[],[],[],[]), ...        
         'spikes',make_clean_params([],[0.5 1],[],[],[],[],[],[],'on',[]), ...
         'drifts',make_clean_params([],[0.5 1],[],[],[],[],[],[],[],[]), ...
         'channels',make_clean_params({},[],[],[],[],'on',[],[],[],[]), ...
         'dropouts',make_clean_params({},[],[],[],[],[],'on',[],[],[]), ...
         'bursts',make_clean_params({},[],[],[],[],[],[],'on',[],[]), ...
         'windows',make_clean_params({},[],[],[],'on',[],[],[],[],[]), ...
         'drifts_channels',make_clean_params({},[0.5 1],[],[],[],'on',[],[],[],[]), ...
         'drifts_bursts',make_clean_params({},[0.5 1],[],[],[],[],[],'on',[],[]), ...
         'drifts_windows',make_clean_params({},[0.5 1],[],[],'on',[],[],[],[],[]), ...
         'drifts_channels_dropouts',make_clean_params({},[0.5 1],[],[],[],'on','on',[],[],[]), ...
         'drifts_bursts_windows',make_clean_params({},[0.5 1],[],[],'on',[],[],'on',[],[]), ...
         'drifts_channels_bursts',make_clean_params({},[0.5 1],[],[],[],'on',[],'on',[],[]), ...
         'drifts_channels_windows',make_clean_params({},[0.5 1],[],[],'on','on',[],[],[],[]), ...
         'drifts_channels_bursts_windows',make_clean_params({},[0.5 1],[],[],'on','on',[],'on',[],[]), ...
         'drifts_channels_dropouts_bursts',make_clean_params({},[0.5 1],[],[],[],'on','on','on',[],[]), ...
         'drifts_channels_dropouts_windows',make_clean_params({},[0.5 1],[],[],'on','on','on',[],[],[]), ...
         'drifts_channels_dropouts_bursts_windows',make_clean_params({},[0.5 1],[],[],'on','on','on','on',[],[]), ...
         '1.1-beta',make_clean_params('on',[0.5 1],[],'off','on','on','on','on','off','off'), ...
         '1.1-beta-nowindow',make_clean_params('on',[0.5 1],[],'off','off','on','on','on','off','off'), ...
         '1.1-beta-nobursts',make_clean_params('on',[0.5 1],[],'off','on','on','on','off','off','off'), ...
         '1.1-beta-nonodropouts',make_clean_params('on',[0.5 1],[],'off','on','on','off','on','off','off'), ...
         ... % legacy settings
         'highpass',make_clean_params([],[0.1 1],[],[],[],[],[],[],[],[]), ...
         'drycap',make_clean_params({},[0.1 1],[],[],{'flag_quantile',0.16},{'min_corr',0.35,'ignored_quantile',0.2},[],{'stddev_cutoff',5},[],[]), ...
         ... % removed formerly deprecated settings
         ... % 'seated',make_clean_params({},[0.1 1],[],[],{'flag_quantile',0.16},{'min_corr',0.4},[],{'stddev_cutoff',5},[],[]), ...
         ... % 'noisy',make_clean_params({},[0.1 1],[],[],{'flag_quantile',0.2},{'min_corr',0.45},[],{'stddev_cutoff',5},[],[]), ...
         ... % 'walking',make_clean_params({},[0.1 1],[],[],{'flag_quantile',0.275},{'min_corr',0.5},[],{'stddev_cutoff',5},[],[]), ...
         ... % 'running',make_clean_params({},[0.1 1],[],[],{'flag_quantile',0.3},{'min_corr',0.55},[],{'stddev_cutoff',5},[],[]), ...
         ... % 'sprinting',make_clean_params({},[0.1 1],[],[],{'flag_quantile',0.4},{'min_corr',0.6},[],{'stddev_cutoff',5},[],[]), ...
         ... % '2013.1',make_clean_params({},[0.1 1],[],[],{'flag_quantile',0.16},{'min_corr',0.4},[],{'stddev_cutoff',5},[],[]), ...         
        },'Artifact removal setting. Determines the aggressiveness of the cleaning functions. The settings that hold version numbers are the default settings for the respective BCILAB version (for forward/backward compatibility). The settings that describe situations are currently mostly legacy settings that use inferior methods.'), ...
    arg({'retain_phases','RetainPhases'},false,[],'Retain signal phases. If this is checked, the drift-correction will be done using a linear-phase FIR filter (which incurs significant signal delay) instead of IIR.'),...
    arg({'prefer_fir','PreferFIR'},true,[],'Prefer FIR filters over IIR. The IIR filters make extensive use of the signal processing toolbox.'),...
    arg({'causal_filtering','CausalFiltering'},true,[],'Perform causal filtering. Required for online processing, strongly recommended for any type of prediction-related offline processing but potentially useful for plotting and interpretation.','guru',true),...
    arg({'initialize_on','InitializeOn'},[],[0 0 300 Inf],'Initialize on time range. If a time range is given as [start,end], either in seconds or as fractions of the whole data (if both <= 1), then where applicable the filters will be initialized only on that subset of the whole data. As a result, artifact filters will not have to be retrained in each cross-validation fold.','shape','row'),...
    arg({'iir_type','IIRType'},'butterworth', {'butterworth','chebychev1','chebychev2','elliptic','yule-walker'}, 'Drift filter type, if IIR. Butterworth has a flat response overall but a slow/gentle rolloff. Chebychev Type I has a steep rolloff, but strong passband ripples. Chebychev Type II has a flat passband response, but a slower rolloff than Type I. The elliptic filter has the steepest rolloff (or lowest latency at comparable steepness) but passband rippling. Yule-walker is enabled implicitly for free-form filter design.'), ...
    arg_deprecated({'linear_reference','LinearArtifactReference'},[],[],'Linear artifact reference channel(s). Labels of any channels that are direct measures of artifacts that shall be removed. Can get slow if you have many such channels (e.g., neckband).','type','cellstr','shape','row'),...
    arg_deprecated({'reference_len','LinearReferenceLength'},3,[0 1 15 Inf],'Linear reference length. The length of the assumed temporal dependencies between artifact channel content and EEG channel contents, in samples. Can get slow if this is very long (e.g., when removing entire VEPs).'), ...
    arg_deprecated({'have_flatlines','HaveFlatlines'},true,[],'Flatline channels. Whether the data may contain flat-line channels.'), ...
    arg_deprecated({'have_broken_chans','HaveBrokenChannels'},true,[],'Broken channels. Whether the data may contain broken channels.'), ...
    arg_deprecated({'have_channel_dropouts','HaveChannelDropouts'},true,[],'Channels drop-outs. Whether the data may contain channels that temporarily drop out and come back.'), ...
    arg_deprecated({'have_spikes','HaveSpikes'},false,[],'Spikes in the data. Whether the data may contain spikes.'), ...
    arg_deprecated({'have_bursts','HaveBursts'},true,[],'Remove bursts from data. Whether the data may contain local bursts or peaks (in subspaces). Only useful for engineering purposes as this will obliterate a fraction of the EEG in ways that are hard to reason about in neuroscience studies.'));


% --- flat-line removal ---

if cleansetting.flatlines.arg_selection
    signal = flt_clean_flatlines(cleansetting.flatlines,'initialize_on',initialize_on,'signal',signal); end

% --- spike removal ---

% remove local spikes using running median and median absolute deviation
if cleansetting.spikes.arg_selection
    signal = flt_clean_spikes(cleansetting.spikes,'signal',signal); end

% --- high-pass drift correction ---

% remove drifts using an IIR filter
if ~isempty(cleansetting.drifts)
    if causal_filtering
        if retain_phases
            signal = flt_fir(signal,cleansetting.drifts,'highpass'); 
        else
            if prefer_fir
                signal = flt_fir(signal,cleansetting.drifts,'highpass','minimum-phase'); 
            else
                signal = flt_iir(signal,cleansetting.drifts,'highpass',iir_type); 
            end
        end
    else
        signal = flt_fir(signal,cleansetting.drifts,'highpass','zero-phase');         
    end
end

% --- low-pass HF noise removal ---

if cleansetting.hf_noise.arg_selection    
    type = quickif(causal_filtering,quickif(retain_phases,'linear-phase','minimum-phase'),'zero-phase'); 
    signal = flt_fir(cleansetting.hf_noise,'Signal',signal,'Type',type);
end

% --- linear reference removal ---

% regress out any linearly related artifact contents in the EEG signal (and remove the reference channels, too)
if ~isempty(linear_reference)
    error('This setting is not available here any more -- use the checkbox under DataSetting.'); end
if cleansetting.regression.arg_selection
    signal = flt_eog(cleansetting.regression,'signal',signal); end

% --- bad channel removal ---

% remove bad channels using a correlation measure
if cleansetting.channels.arg_selection
    signal = flt_clean_channels(cleansetting.channels,'initialize_on',initialize_on,'signal',signal); end

% --- channel glitch handling ---

if cleansetting.dropouts.arg_selection
    signal = flt_repair_channels(cleansetting.dropouts,'initialize_on',initialize_on,'signal',signal); end

% --- burst subspace removal ---

% remove local bursts using ASR
if cleansetting.pcasubspace.arg_selection
    signal = flt_repair_bursts(cleansetting.pcasubspace,'initialize_on',initialize_on,'signal',signal); end

% --- bad window removal ---

% remove extreme data periods using a signal power measure
if cleansetting.windows.arg_selection
    signal = flt_clean_windows(cleansetting.windows,'signal',signal); end

% --- spectral shaping ---

% run a signal-shaping final FIR filter
if cleansetting.shaping.arg_selection
    signal = flt_fir(cleansetting.shaping,'signal',signal); end


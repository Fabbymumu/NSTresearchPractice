function needs_shutdown = env_acquire_cluster(varargin)
% Acquire a cluster using the currently configured acquire options.
% NeedsShutdown = env_acquire_cluster(Overrides...)
%
% The behavior of this function is governed by the configuration variable acquire_options that can
% be set either in the config file or in the "Cluster Settings" GUI dialog. Generally, this function
% will (if supported by the OS), check which of the desired cluster resources are already up, and
% start what still needs to be started. There is no guarantee that the cluster resources actually
% start successfully (and don't crash, etc), the function just tries its best. After that, the
% function will start a "heartbeat" timer that periodically tells the cluster resources that it is
% still interested in keeping them alive. Depending on how the cluster was configured, it may shut
% down the resources after they are no longer needed (e.g., for cost reasons). 
%
% The heartbeat signal can be disabled by calling env_release_cluster or pressing the "request
% cluster availability" button in the GUI toolbar for a second time.
%
% In:
%   Overrides...: optionally override arguments for the cluster acquisition method (e.g.
%                  par_getworkers_ssh)
%
%   NoRelease : don't release workers after having acquired them
%
% Out:
%   NeedsShutdown : whether the cluster shall be shut down via env_release_cluster
%
%                                Christian Kothe, Swartz Center for Computational Neuroscience, UCSD
%                                2012-04-12

global tracking;
import java.io.*
import java.net.*
import java.lang.*

needs_shutdown = false;
no_release = false;
if ~strcmp(par_globalsetting('engine'),'local')
    disp('env_acquire_cluster: cluster already running.');    
else
    % interpret as cell array of arguments to par_getworkers_ssh
    opts = hlp_varargin2struct(varargin,tracking.acquire_options{:});
    if isfield(opts,'NoRelease')
        no_release = true;
        opts = rmfield(opts,'NoRelease');
    end
    arguments = hlp_struct2varargin(opts);
    method = tracking.acquire_method;
    if ~ischar(method)
        error('The given worker acquire method (global tracking.acquire_method) must be a string, but was: %s',hlp_tostring(method,1000)); end
    if isempty(arguments)
        disp('No settings for acquiring the cluster have been specified, no startup command will be issued.'); 
    elseif ~iscell(arguments)
        disp('The acquire_options parameter should be a cell array of name-value pairs which form arguments to par_getworkers_ssh.');
    elseif isunix    
        % invoke, but also impose default arguments (if unspecified)
        % by default, workers do not recruit (but only list) other workers, preventing a cascading effect
        try
            [pool,logpaths] = feval(['par_getworkers_' lower(method)],arguments{:});
            par_globalsetting('pool',pool);
            par_globalsetting('logfiles',logpaths);
            par_globalsetting('engine','BLS');
            disp('Set default compute scheduler to BLS (parallel).');
        catch e
            disp('Could not acquire worker machines; traceback: ');
            env_handleerror(e);
        end
    else
        disp('Cannot automatically acquire hosts from a non-UNIX system.');
    end

    % start the heartbeat timer
    pool = par_globalsetting('pool');
    if ~isempty(pool)
        fprintf('Initiating heartbeat signal... ');
        tracking.cluster_requested = {};    
        % for each endpoint in the pool...
        for p=1:length(pool)
            % remove the pid@ portion from the endpoint
            pos = pool{p}=='@';
            if any(pos)
                pool{p} = pool{p}(find(pos,1)+1:end); end
            % make a new socket
            sock = DatagramSocket();
            % and "connect" it to the worker endpoint (its heartbeat server)
            endpoint = hlp_split(pool{p},':');
            sock.connect(InetSocketAddress(endpoint{1}, str2num(endpoint{2})));
            tracking.cluster_requested{p} = sock;
        end
        % start a timer that sends the heartbeat (every 30 seconds)
        start(timer('ExecutionMode','fixedRate', 'Name','heartbeat_timer', 'Period',15, ...
            'TimerFcn',@(timer_handle,varargin)send_heartbeat(timer_handle)));
        disp('success.');
    else
        tracking.cluster_requested = true;
    end
    needs_shutdown = true;
end

if no_release
    needs_shutdown = false; end
    


% called periodically to send heartbeat messages over the network
function send_heartbeat(timer_handle)
import java.io.*
import java.net.*
import java.lang.*
global tracking;
try
    if ~isfield(tracking,'cluster_requested') || isempty(tracking.cluster_requested) || ~iscell(tracking.cluster_requested)
        error('ouch!'); end
    
    % for each socket in the list of heartbeat sockets...
    for p=1:length(tracking.cluster_requested)
        try
            % send the message
            tmp = DatagramPacket(uint8('dsfjk45djf'),10);
            tracking.cluster_requested{p}.send(tmp);
        catch e
            % some socket problem: ignored.
        end
    end
catch e
    % issue (most likely the request has been cancelled) stop & sdelete the heartbeat timer
    stop(timer_handle);
    delete(timer_handle);
    disp('Heartbeat signal stopped.');
end

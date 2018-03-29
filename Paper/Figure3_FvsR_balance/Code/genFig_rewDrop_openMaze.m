%% STATE-SPACE PARAMETERS
addpath('../../../');
clear;
setParams;
params.maze             = zeros(6,9); % zeros correspond to 'visitable' states
params.maze(2:4,3)      = 1; % wall
params.maze(1:3,8)      = 1; % wall
params.maze(5,6)        = 1; % wall
%params.s_end            = [1,9;6,9]; % goal state (in matrix notation)
params.s_end            = [1,9]; % goal state (in matrix notation)
params.s_start          = [3,1]; % beginning state (in matrix notation)
params.s_start_rand     = true; % Start at random locations after reaching goal

%% OVERWRITE PARAMETERS
params.N_SIMULATIONS    = 100; % number of times to run the simulation
params.MAX_N_STEPS      = 1e5; % maximum number of steps to simulate
params.MAX_N_EPISODES   = 50; % maximum number of episodes to simulate (use Inf if no max) -> Choose between 20 and 100
params.nPlan            = 20; % number of steps to do in planning (set to zero if no planning or to Inf to plan for as long as it is worth it)

params.setAllGainToOne  = false; % Set the gain term of all items to one (for illustration purposes)
params.setAllNeedToOne  = false; % Set the need term of all items to one (for illustration purposes)
params.rewSTD           = 0.1; % reward standard deviation (can be a vector -- e.g. [1 0.1])
params.softmaxT         = 0.2; % soft-max temperature -> higher means more exploration and, therefore, higher gains, and in tern more reverse replay
params.gamma            = 0.90; % discount factor

params.updIntermStates  = true; % Update intermediate states when performing n-step backup
params.baselineGain     = 1e-10; % Gain is set to at least this value (interpreted as "information gain")

params.alpha            = 1; % learning rate for real experience (non-bayesian)
params.copyQinPlanBkps  = false; % Copy the Q-value (mean and variance) on planning backups (i.e., LR=1.0)
params.copyQinGainCalc  = true; % Copy the Q-value (mean and variance) on gain calculation (i.e., LR=1.0)

params.PLOT_STEPS       = false; % Plot each step of real experience
params.PLOT_Qvals       = false; % Plot Q-values
params.PLOT_PLANS       = false; % Plot each planning step
params.PLOT_EVM         = false; % Plot need and gain

params.probNoReward     = 0.5; % probability of receiving no reward

saveStr = input('Do you want to produce figures (y/n)? ','s');
if strcmp(saveStr,'y')
    saveBool = true;
else
    saveBool = false;
end


%% RUN SIMULATION
rng(mean('replay'));
for k=1:params.N_SIMULATIONS
    simData(k) = replaySim(params);
end


%% ANALYSIS PARAMETERS
minNumCells = 5;
minFracCells = 0;
runPermAnalysis = true; % Run permutation analysis (true or false)
nPerm = 500; % Number of permutations for assessing significance of an event


%% INITIALIZE VARIABLES
forwardCount_baseline = zeros(length(simData),numel(params.maze));
reverseCount_baseline = zeros(length(simData),numel(params.maze));
forwardCount_rewShift = zeros(length(simData),numel(params.maze));
reverseCount_rewShift = zeros(length(simData),numel(params.maze));
nextState = nan(numel(params.maze),4);


%% RUN ANALYSIS

% Get action consequences from stNac2stp1Nr()
for s=1:numel(params.maze)
    [I,J] = ind2sub(size(params.maze),s);
    st=nan(1,2);
    st(1)=I; st(2) = J;
    for a=1:4
        [~,~,stp1i] = stNac2stp1Nr(st,a,params);
        nextState(s,a) = stp1i;
    end
end

for k=1:length(simData)
    fprintf('Simulation #%d\n',k);
    % Identify candidate replay events
    candidateEvents = find(cellfun('length',simData(k).replay.state)>=max(sum(params.maze(:)==0)*minFracCells,minNumCells));
    lapNum = [0;simData(k).numEpisodes(1:end-1)] + 1;
    lapNum_events = lapNum(candidateEvents);
    agentPos = simData(k).expList(candidateEvents,1);
    rewRec = simData(k).expList(candidateEvents,3);
    for e=1:length(candidateEvents)
        eventState = simData(k).replay.state{candidateEvents(e)};
        eventAction = simData(k).replay.action{candidateEvents(e)};
        
        % Identify break points in this event, separating event into
        % sequences
        eventDir = cell(1,length(eventState)-1);
        breakPts = 0; % Save breakpoints that divide contiguous replay events
        for i=1:(length(eventState)-1)
            % If state(i) and action(i) leads to state(i+1): FORWARD
            if nextState(eventState(i),eventAction(i)) == eventState(i+1)
                eventDir{i} = 'F';
            end
            % If state(i+1) and action(i+1) leads to state(i): REVERSE
            if nextState(eventState(i+1),eventAction(i+1)) == eventState(i)
                eventDir{i} = 'R';
            end
            
            % Find if this is a break point
            if isempty(eventDir{i})
                breakPts = [breakPts (i-1)];
            elseif i>1
                if ~strcmp(eventDir{i},eventDir{i-1})
                    breakPts = [breakPts (i-1)];
                end
            end
            if i==(length(eventState)-1)
                breakPts = [breakPts i];
            end
        end
        
        % Break this event into segments of sequential activity
        for j=1:(numel(breakPts)-1)
            thisChunk = (breakPts(j)+1):(breakPts(j+1));
            if (length(thisChunk)+1) >= minNumCells
                % Extract information from this sequential event
                replayDir = eventDir(thisChunk);
                replayState = eventState([thisChunk (thisChunk(end)+1)]);
                replayAction = eventAction([thisChunk (thisChunk(end)+1)]);
                
                % Assess the significance of this event
                %allPerms = cell2mat(arrayfun(@(x)randperm(length(replayState)),(1:nPerm)','UniformOutput',0));
                sigBool = true; %#ok<NASGU>
                if runPermAnalysis
                    fracFor = nanmean(strcmp(replayDir,'F'));
                    fracRev = nanmean(strcmp(replayDir,'R'));
                    disScore = fracFor-fracRev;
                    dirScore_perm = nan(1,nPerm);
                    for p=1:nPerm
                        thisPerm = randperm(length(replayState));
                        replayState_perm = replayState(thisPerm);
                        replayAction_perm = replayAction(thisPerm);
                        replayDir_perm = cell(1,length(replayState_perm)-1);
                        for i=1:(length(replayState_perm)-1)
                            if nextState(replayState_perm(i),replayAction_perm(i)) == replayState_perm(i+1)
                                replayDir_perm{i} = 'F';
                            end
                            if nextState(replayState_perm(i+1),replayAction_perm(i+1)) == replayState_perm(i)
                                replayDir_perm{i} = 'R';
                            end
                        end
                        fracFor = nanmean(strcmp(replayDir_perm,'F'));
                        fracRev = nanmean(strcmp(replayDir_perm,'R'));
                        dirScore_perm(p) = fracFor-fracRev;
                    end
                    dirScore_perm = sort(dirScore_perm);
                    lThresh_score = dirScore_perm(floor(nPerm*0.025));
                    hThresh_score = dirScore_perm(ceil(nPerm*0.975));
                    if (disScore<lThresh_score) || (disScore>hThresh_score)
                        sigBool = true;
                    else
                        sigBool = false;
                    end
                end
                
                % Add significant events to 'bucket'
                if sigBool
                    reward_tsi = ismember(simData(k).expList(1:candidateEvents(e),4),sub2ind(size(params.maze),params.s_end(:,1),params.s_end(:,2)));
                    lastReward_tsi = find(reward_tsi,1,'last');
                    lastReward_mag = simData(k).expList(lastReward_tsi,3);
                    if replayDir{1}=='F'
                        if abs(lastReward_mag-1)<abs(lastReward_mag-0)
                            forwardCount_baseline(k,agentPos(e)) = forwardCount_baseline(k,agentPos(e)) + 1;
                        else
                            forwardCount_rewShift(k,agentPos(e)) = forwardCount_rewShift(k,agentPos(e)) + 1;
                        end
                    elseif replayDir{1}=='R'
                        if abs(lastReward_mag-1)<abs(lastReward_mag-0)
                            reverseCount_baseline(k,agentPos(e)) = reverseCount_baseline(k,agentPos(e)) + 1;
                        else
                            reverseCount_rewShift(k,agentPos(e)) = reverseCount_rewShift(k,agentPos(e)) + 1;
                        end
                    end
                end
            end
        end
    end
end

preplayF_baseline = nansum(forwardCount_baseline(:,[1:49 51:54]),2) ./ ((1-params.probNoReward)*params.MAX_N_EPISODES);
replayF_baseline = nansum(forwardCount_baseline(:,50),2) ./ ((1-params.probNoReward)*params.MAX_N_EPISODES);
preplayR_baseline = nansum(reverseCount_baseline(:,[1:49 51:54]),2) ./ ((1-params.probNoReward)*params.MAX_N_EPISODES);
replayR_baseline = nansum(reverseCount_baseline(:,50),2) ./ ((1-params.probNoReward)*params.MAX_N_EPISODES);

preplayF_rewShift = nansum(forwardCount_rewShift(:,[1:49 51:54]),2) ./ (params.probNoReward*params.MAX_N_EPISODES);
replayF_rewShift = nansum(forwardCount_rewShift(:,50),2) ./ (params.probNoReward*params.MAX_N_EPISODES);
preplayR_rewShift = nansum(reverseCount_rewShift(:,[1:49 51:54]),2) ./ (params.probNoReward*params.MAX_N_EPISODES);
replayR_rewShift = nansum(reverseCount_rewShift(:,50),2) ./ (params.probNoReward*params.MAX_N_EPISODES);


%% PLOT

% Forward-vs-Reverse
figure(1); clf;
subplot(1,3,1);
f1 = bar([nanmean(preplayF_baseline) nanmean(replayF_baseline) ; nanmean(preplayR_baseline) nanmean(replayR_baseline)]);
legend({'Preplay','Replay'},'Location','NortheastOutside');
f1(1).FaceColor=[1 1 1]; % Replay bar color
f1(1).LineWidth=1;
f1(2).FaceColor=[0 0 0]; % Replay bar color
f1(2).LineWidth=1;
set(f1(1).Parent,'XTickLabel',{'Forward correlated','Reverse correlated'});
ylim([0 1]);
ylabel('Events/Lap');
grid on
title('Baseline (1x)');

subplot(1,3,2);
f1 = bar([nanmean(preplayF_rewShift) nanmean(replayF_rewShift) ; nanmean(preplayR_rewShift) nanmean(replayR_rewShift)]);
legend({'Preplay','Replay'},'Location','NortheastOutside');
f1(1).FaceColor=[1 1 1]; % Replay bar color
f1(1).LineWidth=1;
f1(2).FaceColor=[0 0 0]; % Replay bar color
f1(2).LineWidth=1;
set(f1(1).Parent,'XTickLabel',{'Forward correlated','Reverse correlated'});
ylim([0 1]);
ylabel('Events/Lap');
grid on
title('Reward drop (0x)');

subplot(1,3,3);
F_baseline = nanmean(replayF_baseline+preplayF_baseline);
F_rewShift = nanmean(replayF_rewShift+preplayF_rewShift);
R_baseline = nanmean(replayR_baseline+preplayR_baseline);
R_rewShift = nanmean(replayR_rewShift+preplayR_rewShift);
load('genFig_FvsR_openMaze.mat','preplayF','replayF','preplayR','replayR')
F_orig = nanmean(replayF+preplayF);
R_orig = nanmean(replayR+preplayR);
f1 = bar([100*((F_baseline/F_orig)-1) 100*((F_rewShift/F_orig)-1) ; 100*((R_baseline/R_orig)-1) 100*((R_rewShift/R_orig)-1)]);
legend({'Unchanged','0x reward'},'Location','NortheastOutside');
set(f1(1).Parent,'XTickLabel',{'Forward correlated','Reverse correlated'});
ylim([-200 200]);
grid on
title('Changes from baseline');

set(gcf,'Position',[234         908        1651         341])


%% EXPORT FIGURE
if saveBool
    save genFig_rewDrop_openMaze.mat

    % Set clipping off
    set(gca, 'Clipping', 'off');
    set(gcf, 'Clipping', 'off');
    
    set(gcf, 'renderer', 'painters');
    export_fig(['../Parts/' mfilename], '-pdf', '-eps', '-q101', '-nocrop', '-painters');
    %print(filename,'-dpdf','-fillpage')
end


% From the README:
%
% The ground-truth poses for the dataset are provided as .mat files in 'gt_poses' directory.
% 
% The pose files are given as, pose_<TrackIndex>_<Index>.mat
% and the images are given as,  img_<TrackIndex>_<Index>.mat
% 
% <TrackIndex> is the index of the continuous image sequence (activity track)
% <Index> is just the image index in this evaluation set.
%
% Each pose file contains the location of 10 parts (torso and head each consists of two points),
%
%      pose(1,:) -> torso upper point
%      pose(2,:) -> torso lower point
%      pose(3,:) -> right shoulder
%      pose(4,:) -> left shoulder
%      pose(5,:) -> right elbow
%      pose(6,:) -> left elbow
%      pose(7,:) -> right wrist
%      pose(8,:) -> left wrist
%      pose(9,:) -> right hand
%      pose(10,:)-> left hand
%      pose(11,:)-> head upper point
%      pose(12,:)-> head lower point

function [mpii_data, train_pairs, val_pairs] = get_mpii_cooking(dest_dir, cache_dir)
%GET_MPII_COOKING Fetches continuous pose estimation data from MPII
MPII_POSE_URL = 'http://datasets.d2.mpi-inf.mpg.de/MPIICookingActivities/poseChallenge-1.1.zip';
MPII_CONTINUOUS_URL = 'http://datasets.d2.mpi-inf.mpg.de/MPIICookingActivities/poseChallengeContinuous-1.0.zip';
CONTINUOUS_DEST_PATH = fullfile(dest_dir, 'mpii-cooking-pose-challenge-continuous');
POSE_DEST_PATH = fullfile(dest_dir, 'mpii-cooking-pose-challenge');
CONTINUOUS_CACHE_PATH = fullfile(cache_dir, 'poseChallengeContinuous-1.0.zip');
POSE_CACHE_PATH = fullfile(cache_dir, 'poseChallenge-1.1.zip');
% We only care about images with two frames in between them (so every third
% frame)
FRAME_SKIP = 2;

% First we get the (much larger) continuous pose estimation dataset
if ~exist(CONTINUOUS_DEST_PATH, 'dir')
    assert(~~exist(CONTINUOUS_CACHE_PATH, 'file'));  % We can't download this since I don't know where it is :P
    if ~exist(CONTINUOUS_CACHE_PATH, 'file')
        fprintf('Downloading MPII continuous pose challenge from %s\n', MPII_CONTINUOUS_URL);
        websave(CONTINUOUS_CACHE_PATH, MPII_CONTINUOUS_URL);
    end
    fprintf('Extracting continuous MPII pose challenge data to %s\n', CONTINUOUS_DEST_PATH);
    unzip(CONTINUOUS_CACHE_PATH, CONTINUOUS_DEST_PATH);
end

% Next we grab the smaller original pose estimation dataset, which has a
% continuous (but low-FPS) training set but discontinuous testing set.
% We'll use the training set from that as our validation set.
if ~exist(POSE_DEST_PATH, 'dir')
    assert(~~exist(POSE_CACHE_PATH, 'file'));  % We can't download this since I don't know where it is :P
    if ~exist(POSE_CACHE_PATH, 'file')
        fprintf('Downloading MPII pose challenge from %s\n', MPII_POSE_URL);
        websave(POSE_CACHE_PATH, MPII_POSE_URL);
    end
    fprintf('Extracting basic MPII pose challenge data to %s\n', POSE_DEST_PATH);
    unzip(POSE_CACHE_PATH, POSE_DEST_PATH);
end

data_path = fullfile(cache_dir, 'mpii_data.mat');
% regen_pairs tells us whether we should regenerate pairs regardless of
% whether the file exists.
regen_pairs = false;
if ~exist(data_path, 'file')
    fprintf('Regenerating data\n');
    mpii_cont_data = load_files_continuous(CONTINUOUS_DEST_PATH);
    mpii_basic_data = load_files_basic(POSE_DEST_PATH);
    
    % TODO: Make sure I handle the two data sets correctly
    % Now we need to make sure we have scene numbers
    mpii_data = split_mpii_scenes(mpii_data, 0.2);
    
    save(data_path, 'mpii_data');
    regen_pairs = true;
else
    fprintf('Loading data from file\n');
    loaded = load(data_path);
    mpii_data = loaded.mpii_data;
end

% Now split into training and validation sets TODO
pair_path = fullfile(cache_dir, 'mpii_pairs.mat');
if ~exist(pair_path, 'file') || regen_pairs
    fprintf('Generating pairs\n');
    [all_pairs, pair_scenes] = find_pairs(mpii_data, FRAME_SKIP);
    
    % Choose which scenes to use for training and which to use for
    % validation
    all_scenes = unique(pair_scenes);
    all_scenes = all_scenes(randperm(length(all_scenes)));
    num_train_scenes = floor(length(all_scenes) * 0.7);
    train_scenes = all_scenes(1:num_train_scenes);
    val_scenes = all_scenes(num_train_scenes+1:end);
    disp(train_scenes);
    disp(val_scenes);
    
    % Find the pair indices corresponding to the chosen scenes
    train_indices = ismember(pair_scenes, train_scenes);
    val_indices = ismember(pair_scenes, val_scenes);
    fprintf('Have %i training pairs and %i validation pairs\n', ...
        sum(train_indices), sum(val_indices));
    
    % Now save!
    train_pairs = all_pairs(train_indices, :);
    val_pairs = all_pairs(val_indices, :);
    save(pair_path, 'train_pairs', 'val_pairs');
else
    fprintf('Loading pairs from file\n');
    loaded = load(pair_path);
    % Yes, I know I could just load() without assigning anything, but I
    % like this way better.
    train_pairs = loaded.train_pairs;
    val_pairs = loaded.val_pairs;
end
end

function cont_data = load_files_continuous(dest_path)
pose_dir = fullfile(dest_path, 'data', 'gt_poses');
pose_fns = dir(pose_dir);
pose_fns = pose_fns(3:end); % Remove . and ..
cont_data = struct(); % Silences Matlab warnings about growing arrays
for i=1:length(pose_fns)
    data_fn = pose_fns(i).name;
    [track_index, index] = parse_continuous_fn(data_fn);
    % "track_index" is the index within the dataset for the action
    % track. "index" is the index within the dataset. They really could
    % have picked a more optimal name :/
    cont_data(i).frame_no = index;
    cont_data(i).action_track_index = track_index;
    file_name = sprintf('img_%06i_%06i.jpg', track_index, index);
    cont_data(i).image_path = fullfile(dest_path, 'data', 'images', file_name);
    loaded = load(fullfile(pose_dir, data_fn), 'pose');
    cont_data(i).joint_locs = loaded.pose;
    cont_data(i).is_val = false;
end
cont_data = sort_by_frame(cont_data);
end

function basic_data = load_files_basic()
pose_dir = fullfile(dest_path, 'data', 'train_data', 'gt_poses');
pose_fns = dir(pose_dir);
pose_fns = pose_fns(3:end);
basic_data = struct(); % Silences Matlab warnings about growing arrays
for i=1:length(pose_fns)
    data_fn = pose_fns(i).name;
    frame_no = parse_continuous_fn(data_fn);
    basic_data(i).frame_no = frame_no;
    file_name = sprintf('img_%06i.jpg', frame_no);
    basic_data(i).image_path = fullfile(dest_path, 'data', 'train_data', 'images', file_name);
    loaded = load(fullfile(pose_dir, data_fn), 'pose');
    basic_data(i).joint_locs = loaded.pose;
    basic_data(i).is_val = true;
end
basic_data = sort_by_frame(basic_data);
end

function sorted = sort_by_frame(data)
[~, sorted_indices] = sort([data.frame_no]);
sorted = data(sorted_indices);
end

function [track_index, index] = parse_continuous_fn(fn)
% Parse a filename like pose_<TrackIndex>_<Index>.mat
tokens = regexp(fn, '[^\d]*(\d+)_(\d+)', 'tokens');
assert(length(tokens) >= 1);
assert(length(tokens{1}) == 2);
track_index = str2double(tokens{1}{1});
index = str2double(tokens{1}{2});
end

function index = parse_basic_fn(fn)
tokens = regexp(fn, '[^\d]*(\d+)', 'tokens');
assert(length(tokens) >= 1);
assert(length(tokens{1}) == 1);
index = str2double(tokens{1}{1});
end

function [pairs, scenes] = find_pairs(mpii_data, frame_skip)
% Find pairs with frame_skip frames between them
frame_nums = [mpii_data.frame_no];
scene_nums = [mpii_data.scene_num];
fst_inds = 1:(length(mpii_data)-frame_skip-1);
snd_inds = fst_inds + frame_skip + 1;
good_inds = (frame_nums(snd_inds) - frame_nums(fst_inds) == frame_skip + 1) ...
    & (scene_nums(fst_inds) == scene_nums(snd_inds));
pairs = cat(2, fst_inds(good_inds)', snd_inds(good_inds)');
scenes = scene_nums(fst_inds(good_inds));
end

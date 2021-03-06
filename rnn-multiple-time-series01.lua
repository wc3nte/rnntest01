-- Multi-variate time-series test
-- modification of the original recurrent-time-series.lua example
-- first two columns contain inputs, last column contains output in the same row (so please note the difference in offsets between this and original examples)

require 'rnn'

cmd = torch.CmdLine()
cmd:text()
cmd:text('Train a multivariate time-series model using RNN')
cmd:option('--rho', 2, 'maximum number of time steps for back-propagate through time (BPTT)')
cmd:option('--hiddenSize', 12, 'number of hidden units used at output of the recurrent layer')
cmd:option('--dataSize', 100, 'total number of time-steps in dataset')
cmd:option('--batchSize', 8, 'number of training samples per batch')
cmd:option('--nIterations', 1000, 'max number of training iterations')
cmd:option('--learningRate', 0.075, 'learning rate')
cmd:text()
local opt = cmd:parse(arg or {})

-- create an inputs/outputs sequence
sequence = torch.Tensor(opt.dataSize,3):fill(0)
i=0.1
for j = 2,opt.dataSize do
sequence[j][1]= i --fill column 1
sequence[j][2] = i + 0.01 --fill column 2
sequence[j][3] = sequence[j][1] + sequence[j][2]--fill column 3
local randomEvent=torch.rand(1)
if randomEvent[1]>0.8 and sequence[j-1][3]>0 then sequence[j][3]=0 end --add random events that affect current and future outputs
if sequence[j-1][3]==0 then sequence[j][3] = -0.5 end
i=i+0.01
if sequence[j][3] >0.99 then i=0 end
end
print('Sequence:'); print(sequence)
print('Sequence length:', sequence:size(1))


-- batch mode

-- create linear offsets
j=-1
offsets = torch.LongTensor(opt.batchSize):apply(function()
    j=j+1
    return j
  end)
print('offsets: ', offsets)

-- RNN
r = nn.Recurrent(
   opt.hiddenSize,
   nn.Linear(3, opt.hiddenSize), -- input layer
   --nn.Linear(opt.hiddenSize, opt.hiddenSize), -- recurrent layer
   nn.LSTM(opt.hiddenSize, opt.hiddenSize), -- recurrent layer
   nn.Tanh(), -- transfer function
   opt.rho
)

rnn = nn.Sequential()
   :add(r)
   :add(nn.Linear(opt.hiddenSize, 1)) 

criterion = nn.MSECriterion() 

-- use Sequencer for better data handling
rnn = nn.Sequencer(rnn)

criterion = nn.SequencerCriterion(criterion)
print("Model :")
print(rnn)

-- train rnn model
minErr = 0 -- report min error
minK = 0
avgErrs = torch.Tensor(opt.nIterations):fill(0)
for k = 1, opt.nIterations do 

   -- 1. create a sequence of rho time-steps
   
   local inputs, targets = {}, {}
   for step = 1, opt.rho do
      -- batch of inputs
      offsets:add(1)
      offsets[offsets:gt(sequence:size(1))] = 1
      inputs[step] = inputs[step] or sequence.new()
      inputs[step]:index(sequence, 1, offsets)
      --inputs[step] = inputs[step]:sub(1,opt.batchSize,1,2) --select inputs from columns 1 and 2
      -- batch of targets
      targets[step] = targets[step] or sequence.new()
      targets[step]:index(sequence, 1, offsets)
      targets[step] = targets[step]:sub(1,opt.batchSize,3,3) --select output from column 3
   end

   -- 2. forward sequence through rnn

   local outputs = rnn:forward(inputs)
   local err = criterion:forward(outputs, targets)
  
   if k%33==0 then 
   for i=1,opt.rho do
      print('iter: ', k, 'element: ', i)
      print('inputs:')
      print(inputs[i])
      print('targets:')
      print(targets[i])
      print('outputs:')
      print(outputs[i])
   end --end for i
   end --end if
   
   -- report errors
 
   print('Iter: ' .. k .. '   Err: ' .. err)
   avgErrs[k] = err
   if avgErrs[k] < minErr then
      minErr = avgErrs[k]
      minK = k
   end

   -- 3. backward sequence through rnn (i.e. backprop through time)
   
   rnn:zeroGradParameters()
   
   local gradOutputs = criterion:backward(outputs, targets)
   local gradInputs = rnn:backward(inputs, gradOutputs)

   -- 4. updates parameters
   
   rnn:updateParameters(opt.learningRate)
end

print('min err: ' .. minErr .. ' on iteration ' .. minK)
